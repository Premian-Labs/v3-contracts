import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  IOracleAdapter,
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
  OptionMathMock,
  OptionMathMock__factory,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy,
  UnderwriterVaultProxy__factory,
  VolatilityOracleMock,
  VolatilityOracleMock__factory,
  IOracleAdapter__factory,
} from '../../../typechain';
import { PoolUtil } from '../../../utils/PoolUtil';
import { getValidMaturity, latest, ONE_DAY } from '../../../utils/time';
import { AdapterType, PoolKey } from '../../../utils/sdk/types';
import { tokens } from '../../../utils/addresses';
import { BigNumber, BigNumberish, Signer } from 'ethers';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { ethers } from 'hardhat';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { expect } from 'chai';
import { now } from 'moment-timezone';

export let deployer: SignerWithAddress;
export let caller: SignerWithAddress;
export let receiver: SignerWithAddress;
export let underwriter: SignerWithAddress;
export let lp: SignerWithAddress;
export let trader: SignerWithAddress;
export let feeReceiver: SignerWithAddress;

export let optionMath: OptionMathMock;

export let vaultImpl: UnderwriterVaultMock;
export let callVaultProxy: UnderwriterVaultProxy;
export let putVaultProxy: UnderwriterVaultProxy;
export let callVault: UnderwriterVaultMock;
export let putVault: UnderwriterVaultMock;

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
): Promise<[pool: IPoolMock, poolAddress: string, poolKey: PoolKey]> {
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
  return [pool, poolAddress, poolKey];
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

  if (log)
    console.log(`Mock oracleAdapter Implementation : ${oracleAdapter.address}`);

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

  if (log) console.log(`volOracle Address : ${volOracle.address}`);

  //=====================================================================================
  // Mock Factory/Pool setup

  strike = parseEther('1500'); // ATM
  maturity = await getValidMaturity(2, 'weeks');

  p = await PoolUtil.deploy(
    deployer, // signer
    tokens.WETH.address, // wrappedNativeToken
    oracleAdapter.address, // chainlinkAdapter
    deployer.address, // feeReceiver
    parseEther('0.1'), // 10% discountPerPool
    true, // log
    true, // isDevMode
  );

  const [callPool, callPoolAddress, callPoolKey] = await createPool(
    strike,
    maturity,
    true,
    deployer,
    base,
    quote,
    oracleAdapter,
    p,
  );

  if (log)
    console.log(`WETH/USDC 1500 Call (ATM) exp. 2 weeks : ${callPoolAddress}`);

  const [putPool, putPoolAddress, putPoolKey] = await createPool(
    strike,
    maturity,
    false,
    deployer,
    base,
    quote,
    oracleAdapter,
    p,
  );

  if (log)
    console.log(`WETH/USDC 1500 Put (ATM) exp. 2 weeks : ${putPoolAddress}`);

  const factoryAddress = p.poolFactory.address;

  //=====================================================================================
  // Mock Vault setup

  vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
    feeReceiver.address,
    volOracle.address,
    p.poolFactory.address,
    p.router.address,
  );
  await vaultImpl.deployed();
  if (log)
    console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

  const _cLevelParams: CLevel = {
    minCLevel: parseEther('1.0'),
    maxCLevel: parseEther('1.2'),
    alphaCLevel: parseEther('3.0'),
    hourlyDecayDiscount: parseEther('0.005'),
  };

  const _tradeBounds: TradeBounds = {
    maxDTE: parseEther('30'),
    minDTE: parseEther('3'),
    minDelta: parseEther('0.1'),
    maxDelta: parseEther('0.7'),
  };

  const lastTimeStamp = Math.floor(new Date().getTime() / 1000);
  // Vault Proxy setup
  callVaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
    vaultImpl.address,
    base.address,
    quote.address,
    oracleAdapter.address,
    'WETH Vault',
    'WETH',
    true,
    _cLevelParams,
    _tradeBounds,
  );
  await callVaultProxy.deployed();
  callVault = UnderwriterVaultMock__factory.connect(
    callVaultProxy.address,
    deployer,
  );
  if (log) console.log(`UnderwriterCallVaultProxy : ${callVaultProxy.address}`);

  putVaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
    vaultImpl.address,
    base.address,
    quote.address,
    oracleAdapter.address,
    'WETH Vault',
    'WETH',
    false,
    _cLevelParams,
    _tradeBounds,
  );
  await putVaultProxy.deployed();
  putVault = UnderwriterVaultMock__factory.connect(
    putVaultProxy.address,
    deployer,
  );
  if (log) console.log(`UnderwriterPutVaultProxy : ${putVaultProxy.address}`);

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
  };
}
