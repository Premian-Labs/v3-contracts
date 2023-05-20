import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
  IVxPremia__factory,
  OptionMathMock,
  OptionMathMock__factory,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy,
  UnderwriterVaultProxy__factory,
  VolatilityOracleMock,
  VaultRegistry,
  VaultRegistry__factory,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../../typechain';
import { PoolUtil } from '../../../utils/PoolUtil';
import { getValidMaturity, latest, ONE_DAY } from '../../../utils/time';
import { AdapterType, PoolKey } from '../../../utils/sdk/types';
import { tokens } from '../../../utils/addresses';
import { BigNumber, BigNumberish, constants } from 'ethers';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { ethers } from 'hardhat';

import {
  AbiCoder,
  keccak256,
  parseEther,
  parseUnits,
  toUtf8Bytes,
} from 'ethers/lib/utils';

import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';

export let deployer: SignerWithAddress;
export let caller: SignerWithAddress;
export let receiver: SignerWithAddress;
export let underwriter: SignerWithAddress;
export let lp: SignerWithAddress;
export let trader: SignerWithAddress;
export let feeReceiver: SignerWithAddress;

export let optionMath: OptionMathMock;

export let vaultRegistryImpl: VaultRegistry;
export let vaultRegistryProxy: ProxyUpgradeableOwnable;
export let vaultRegistry: VaultRegistry;

export let vaultImpl: UnderwriterVaultMock;
export let callVaultProxy: UnderwriterVaultProxy;
export let putVaultProxy: UnderwriterVaultProxy;
export let callVault: UnderwriterVaultMock;
export let putVault: UnderwriterVaultMock;
export let vault: UnderwriterVaultMock;

// Pool Specs
export let p: PoolUtil;
export let maturity: number;
export let strike: BigNumber;
export let poolKey: PoolKey;

interface CLevel {
  minCLevel: BigNumberish;
  maxCLevel: BigNumberish;
  alphaCLevel: BigNumberish;
  hourlyDecayDiscount: BigNumberish;
}

interface TradeBounds {
  maxDTE: BigNumberish;
  minDTE: BigNumberish;
  minDelta: BigNumberish;
  maxDelta: BigNumberish;
}

export let base: ERC20Mock;
export let quote: ERC20Mock;
export let longCall: ERC20Mock;
export let shortCall: ERC20Mock;
export let token: ERC20Mock;
export let oracleAdapter: MockContract;
export let volOracle: VolatilityOracleMock;
export let volOracleProxy: ProxyUpgradeableOwnable;

export const log = true;

export let startTime: number;
export let spot: number;
export let minMaturity: number;
export let maxMaturity: number;

export async function setMaturities(vault: UnderwriterVaultMock) {
  startTime = await latest();
  spot = 2800;
  minMaturity = startTime + 10 * ONE_DAY;
  maxMaturity = startTime + 20 * ONE_DAY;

  const infos = [
    {
      maturity: minMaturity.toString(),
      strikes: [],
      sizes: [],
    },
    {
      maturity: maxMaturity.toString(),
      strikes: [],
      sizes: [],
    },
  ];
  await vault.setListingsAndSizes(infos);
}
export async function addDeposit(
  vault: UnderwriterVaultMock,
  caller: SignerWithAddress,
  amount: number,
  base: ERC20Mock,
  quote: ERC20Mock,
  receiver: SignerWithAddress = caller,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const assetAmount = parseUnits(amount.toString(), await token.decimals()); // todo

  await token.connect(caller).approve(vault.address, assetAmount);
  await vault.connect(caller).deposit(assetAmount, receiver.address);
}

export async function increaseTotalAssets(
  vault: UnderwriterVaultMock,
  amount: number,
  base: ERC20Mock,
  quote: ERC20Mock,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const assetAmount = parseUnits(amount.toString(), await token.decimals());
  await token.mint(vault.address, assetAmount);
  await vault.increaseTotalAssets(parseEther(amount.toString()));
}

export async function increaseTotalShares(
  vault: UnderwriterVaultMock,
  sharesAmount: number,
  receiverAddress: any = null,
) {
  const sharesAmountParsed = parseEther(sharesAmount.toString());
  if (typeof receiverAddress == 'string') {
    await vault.mintMock(receiverAddress, sharesAmountParsed);
  } else {
    await vault.increaseTotalShares(sharesAmountParsed);
  }
  //await vault.approve(vault.address, sharesAmountParsed);
  //await vault.mint(sharesAmountParsed, vault.address);
}

// standard deposit, pricePerShare after single call of addMockDeposit will always equal one
export async function addMockDeposit(
  vault: UnderwriterVaultMock,
  amount: number,
  base: ERC20Mock,
  quote: ERC20Mock,
  sharesAmount: number = amount,
  receiverAddress: any = null,
) {
  // await increaseTotalAssets(vault, amount, base, quote);
  // await increaseTotalShares(vault, sharesAmount, receiverAddress);
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const assetAmount = parseUnits(amount.toString(), await token.decimals());

  if (receiverAddress != null) {
    await token.connect(caller).approve(vault.address, assetAmount);
    await vault.connect(caller).deposit(assetAmount, receiverAddress);
  }
}

export async function createPool(
  strike: BigNumber,
  maturity: number,
  isCall: boolean,
  deployer: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  oracleAdapter: MockContract,
  p: PoolUtil,
) {
  let pool: IPoolMock;

  poolKey = {
    base: base.address,
    quote: quote.address,
    oracleAdapter: oracleAdapter.address,
    strike: strike,
    maturity: BigNumber.from(maturity),
    isCallPool: isCall,
  };

  const tx = await p.poolFactory.deployPool(poolKey, {
    value: parseEther('1'),
  });

  const r = await tx.wait(1);
  const poolAddress = (r as any).events[0].args.poolAddress;
  pool = IPoolMock__factory.connect(poolAddress, deployer);
  return { pool, poolAddress, poolKey };
}

export async function vaultSetup() {
  [deployer, caller, receiver, underwriter, lp, trader, feeReceiver] =
    await ethers.getSigners();

  // Deploy option math
  optionMath = await new OptionMathMock__factory(deployer).deploy();

  //=====================================================================================
  // Deploy ERC20's

  base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
  quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
  longCall = await new ERC20Mock__factory(deployer).deploy('Long', 18);
  shortCall = await new ERC20Mock__factory(deployer).deploy('Short', 18);

  await base.deployed();
  await quote.deployed();
  await longCall.deployed();
  await shortCall.deployed();

  //=====================================================================================
  // Hydrate all accounts with WETH and USDC

  await base.mint(deployer.address, parseEther('1000'));
  await quote.mint(deployer.address, parseEther('1000000'));

  await base.mint(caller.address, parseEther('1000'));
  await quote.mint(caller.address, parseEther('1000000'));

  await base.mint(receiver.address, parseEther('1000'));
  await quote.mint(receiver.address, parseEther('1000000'));

  await base.mint(underwriter.address, parseEther('1000'));
  await quote.mint(underwriter.address, parseEther('1000000'));

  await base.mint(lp.address, parseEther('1000'));
  await quote.mint(lp.address, parseEther('1000000'));

  await base.mint(trader.address, parseEther('1000'));
  await quote.mint(trader.address, parseEther('1000000'));

  //=====================================================================================
  // Mock Oracle Adapter setup

  oracleAdapter = await deployMockContract(deployer, [
    'function isPairSupported(address, address) external view returns (bool, bool)',
    'function upsertPair(address, address) external',
    'function quote(address, address) external view returns (uint256)',
    'function quoteFrom(address, address, uint256) external view returns (uint256)',
    'function describePricingPath(address) external view returns (uint8,address[][],uint8[])',
  ]);

  // Upsert pair is called within deployPool from the PoolFactory contract
  await oracleAdapter.mock.isPairSupported.returns(true, true);
  await oracleAdapter.mock.upsertPair.returns();
  await oracleAdapter.mock.quote.returns(parseUnits('1500', 18));

  await oracleAdapter.mock.describePricingPath
    .withArgs(base.address)
    .returns(
      AdapterType.NONE,
      [['0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE']],
      ['18'],
    );

  await oracleAdapter.mock.describePricingPath
    .withArgs(quote.address)
    .returns(
      AdapterType.NONE,
      [['0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE']],
      ['6'],
    );

  //=====================================================================================
  // Mock Volatility Oracle setup

  let volOracle = await deployMockContract(deployer, [
    'function getVolatility(address token, uint256 spot, uint256 strike, uint256 timeToMaturity) external view returns (uint256)',
    'function getVolatility(address token, uint256 spot, uint256[] memory strike, uint256[] memory timeToMaturity) external view returns (uint256[] memory)',
    'function getRiskFreeRate() external pure returns (uint256)',
  ]);

  await volOracle.mock.getRiskFreeRate.returns(parseEther('0.01'));
  await volOracle.mock.getVolatility
    .withArgs(base.address, parseEther('1500'), [], [])
    .returns([]);

  //=====================================================================================
  // Mock Factory/Pool setup
  strike = parseEther('1500'); // ATM
  maturity = await getValidMaturity(2, 'weeks');
  console.log('maturity', maturity);

  //=====================================================================================
  // vxPREMIA setup
  const premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);

  await premia.mint(caller.address, parseEther('100000'));

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    constants.AddressZero,
    constants.AddressZero,
    premia.address,
    constants.AddressZero,
    constants.AddressZero,
  );

  await vxPremiaImpl.deployed();

  const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
    vxPremiaImpl.address,
  );

  await vxPremiaProxy.deployed();

  const vxPremia = IVxPremia__factory.connect(vxPremiaProxy.address, deployer);

  //=====================================================================================

  p = await PoolUtil.deploy(
    deployer, // signer
    tokens.WETH.address, // wrappedNativeToken
    oracleAdapter.address, // chainlinkAdapter
    deployer.address, // feeReceiver
    parseEther('0.1'), // 10% discountPerPool
    false, // log
    true, // isDevMode
  );

  const {
    pool: callPool,
    poolAddress: callPoolAddress,
    poolKey: callPoolKey,
  } = await createPool(
    strike,
    maturity,
    true,
    deployer,
    base,
    quote,
    oracleAdapter,
    p,
  );

  const {
    pool: putPool,
    poolAddress: putPoolAddress,
    poolKey: putPoolKey,
  } = await createPool(
    strike,
    maturity,
    false,
    deployer,
    base,
    quote,
    oracleAdapter,
    p,
  );

  const factoryAddress = p.poolFactory.address;

  // ====================================================================================

  //=====================================================================================
  // Mock Vault setup

  // 1. Deploy vault registry implementation
  vaultRegistryImpl = await new VaultRegistry__factory(deployer).deploy();
  await vaultRegistryImpl.deployed();

  // 2. Deploy registry proxy
  vaultRegistryProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(vaultRegistryImpl.address);
  await vaultRegistryProxy.deployed();

  vaultRegistry = VaultRegistry__factory.connect(
    vaultRegistryProxy.address,
    deployer,
  );

  // 3. Update settings on the registry for the vault type
  const vaultType = keccak256(toUtf8Bytes('UnderwriterVault'));

  const abi = new AbiCoder();
  const encoding = abi.encode(
    ['uint256[]'],
    [
      [3, 0.005, 1, 1.2, 3, 30, 0.1, 0.7, 0.05, 0.02].map((el) =>
        parseEther(el.toString()),
      ),
    ],
  );
  await vaultRegistry.connect(deployer).updateSettings(vaultType, encoding);

  // 4. Deploy the vault implementation
  vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
    vaultRegistry.address,
    feeReceiver.address,
    volOracle.address,
    p.poolFactory.address,
    p.router.address,
    vxPremia.address,
  );
  await vaultImpl.deployed();

  // 5. Set the vault implementation in for the vault type in the registry
  await vaultRegistry
    .connect(deployer)
    .setImplementation(vaultType, vaultImpl.address);

  // 6. Deploy vault proxy
  const lastTimeStamp = Math.floor(new Date().getTime() / 1000);

  // Deploy call vault proxy
  callVaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
    vaultRegistry.address,
    base.address,
    quote.address,
    oracleAdapter.address,
    'WETH Vault',
    'WETH',
    true,
  );
  await callVaultProxy.deployed();

  callVault = UnderwriterVaultMock__factory.connect(
    callVaultProxy.address,
    deployer,
  );

  // Deploy put vault proxy
  putVaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
    vaultRegistry.address,
    base.address,
    quote.address,
    oracleAdapter.address,
    'WETH Vault',
    'WETH',
    false,
  );
  await putVaultProxy.deployed();

  putVault = UnderwriterVaultMock__factory.connect(
    putVaultProxy.address,
    deployer,
  );

  return {
    deployer,
    caller,
    receiver,
    underwriter,
    lp,
    trader,
    base,
    quote,
    optionMath,
    vaultRegistry,
    callVault,
    putVault,
    volOracle,
    oracleAdapter,
    lastTimeStamp,
    p,
    callPool,
    putPool,
    factoryAddress,
    callPoolKey,
    putPoolKey,
    maturity,
    strike,
    callPoolAddress,
    putPoolAddress,
    feeReceiver,
    vxPremia,
    premia,
  };
}

export async function setup(isCall: boolean, test: any) {
  let { callVault, putVault, base, quote, caller } = await loadFixture(
    vaultSetup,
  );

  vault = isCall ? callVault : putVault;
  token = isCall ? base : quote;
  const decimals = await token.decimals();

  // set pps and totalSupply vault
  const totalSupply = parseEther(test.totalSupply.toString());
  await increaseTotalShares(
    vault,
    parseFloat((test.totalSupply - test.shares).toFixed(12)),
  );
  const pps = parseEther(test.pps.toString());
  const vaultDeposit = parseUnits(
    (test.pps * test.totalSupply).toFixed(12),
    decimals,
  );
  await token.mint(vault.address, vaultDeposit);
  await vault.increaseTotalAssets(
    parseEther((test.pps * test.totalSupply).toFixed(12)),
  );

  // set pps and shares user
  const userShares = parseEther(test.shares.toString());
  await vault.mintMock(caller.address, userShares);
  const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
  await vault.setNetUserDeposit(caller.address, userDeposit);
  const ppsUser = parseEther(test.ppsUser.toString());
  const ppsAvg = await vault.getAveragePricePerShare(caller.address);

  expect(ppsAvg).to.eq(ppsUser);

  expect(await vault.totalSupply()).to.eq(totalSupply);
  expect(await vault.getPricePerShare()).to.eq(pps);

  return { vault, caller, token };
}

export async function setupGetFeeVars(isCall: boolean, test: any) {
  let {
    callVault,
    putVault,
    base,
    quote,
    caller: _caller,
    receiver: _receiver,
    vxPremia,
    premia,
  } = await loadFixture(vaultSetup);

  vault = isCall ? callVault : putVault;
  token = isCall ? base : quote;
  caller = _caller;
  receiver = _receiver;

  // set pps and totalSupply vault
  const totalSupply = parseEther(test.totalSupply.toString());
  await increaseTotalShares(
    vault,
    parseFloat((test.totalSupply - test.shares).toFixed(12)),
  );
  const pps = parseEther(test.pps.toString());
  const vaultDeposit = parseUnits(
    (test.pps * test.totalSupply).toFixed(12),
    await token.decimals(),
  );
  await token.mint(vault.address, vaultDeposit);

  await vault.increaseTotalAssets(
    parseEther((test.pps * test.totalSupply).toFixed(12)),
  );

  // set pps and shares user caller
  const userShares = parseEther(test.shares.toString());
  await vault.mintMock(caller.address, userShares);
  const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
  await vault.setNetUserDeposit(caller.address, userDeposit);
  await vault.setTimeOfDeposit(caller.address, test.timeOfDeposit);

  // check pps is as expected
  const ppsUser = parseEther(test.ppsUser.toString());
  if (test.shares > 0) {
    const ppsAvg = await vault.getAveragePricePerShare(caller.address);
    expect(ppsAvg).to.eq(ppsUser);
  }

  expect(await vault.totalSupply()).to.eq(totalSupply);
  expect(await vault.getPricePerShare()).to.eq(pps);

  await vault.setPerformanceFeeRate(
    parseEther(test.performanceFeeRate.toString()),
  );
  await vault.setManagementFeeRate(
    parseEther(test.managementFeeRate.toString()),
  );

  return { vault, caller, receiver, token, vxPremia, premia };
}

export async function setupBeforeTokenTransfer(isCall: boolean, test: any) {
  let { vault, caller, receiver, token } = await setupGetFeeVars(isCall, test);

  await token.mint(
    vault.address,
    parseUnits(test.protocolFeesInitial.toString(), await token.decimals()),
  );
  await vault.setProtocolFees(parseEther(test.protocolFeesInitial.toString()));
  await vault.setNetUserDeposit(
    receiver.address,
    parseEther(test.netUserDepositReceiver.toString()),
  );

  return { vault, caller, receiver, token };
}
