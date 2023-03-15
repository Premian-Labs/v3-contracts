import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy,
  UnderwriterVaultProxy__factory,
  VolatilityOracleMock,
  VolatilityOracleMock__factory,
} from '../../../typechain';
import { PoolUtil } from '../../../utils/PoolUtil';
import { getValidMaturity } from '../../../utils/time';
import { PoolKey } from '../../../utils/sdk/types';
import { tokens } from '../../../utils/addresses';
import { BigNumber, BigNumberish, Signer } from 'ethers';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { ethers } from 'hardhat';
import { parseEther, parseUnits } from 'ethers/lib/utils';

export let deployer: SignerWithAddress;
export let caller: SignerWithAddress;
export let receiver: SignerWithAddress;
export let underwriter: SignerWithAddress;
export let lp: SignerWithAddress;
export let trader: SignerWithAddress;

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
  await increaseTotalAssets(vault, amount, base, quote);
  await increaseTotalShares(vault, sharesAmount, receiverAddress);
}

export async function vaultSetup() {
  [deployer, caller, receiver, underwriter, lp, trader] =
    await ethers.getSigners();

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
  ]);

  // Upsert pair is called within deployPool from the PoolFactory contract
  await oracleAdapter.mock.isPairSupported.returns(true, true);
  await oracleAdapter.mock.upsertPair.returns();
  await oracleAdapter.mock.quote.returns(parseUnits('1500', 18));

  if (log)
    console.log(`Mock oracleAdapter Implementation : ${oracleAdapter.address}`);

  //=====================================================================================
  // Mock Volatility Oracle setup

  const impl = await new VolatilityOracleMock__factory(deployer).deploy();

  volOracleProxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
    impl.address,
  );

  volOracle = VolatilityOracleMock__factory.connect(
    volOracleProxy.address,
    deployer,
  );

  await volOracle.connect(deployer).addWhitelistedRelayers([deployer.address]);

  const tau = [
    0.0027397260273972603, 0.03561643835616438, 0.09315068493150686,
    0.16986301369863013, 0.4191780821917808,
  ].map((el) => Math.floor(el * 10 ** 12));

  const theta = [
    0.0017692409901229372, 0.01916765969267577, 0.050651452629040784,
    0.10109715579595925, 0.2708994887970898,
  ].map((el) => Math.floor(el * 10 ** 12));

  const psi = [
    0.037206384846952066, 0.0915623614722959, 0.16107355519602318,
    0.2824760899898832, 0.35798035117937516,
  ].map((el) => Math.floor(el * 10 ** 12));

  const rho = [
    1.3478910000157727e-8, 2.0145423645807155e-6, 2.910345029369492e-5,
    0.0003768214425074357, 0.0002539234691761822,
  ].map((el) => Math.floor(el * 10 ** 12));

  const tauHex = await volOracle.formatParams(tau as any);
  const thetaHex = await volOracle.formatParams(theta as any);
  const psiHex = await volOracle.formatParams(psi as any);
  const rhoHex = await volOracle.formatParams(rho as any);

  await volOracle
    .connect(deployer)
    .updateParams([base.address], [tauHex], [thetaHex], [psiHex], [rhoHex]);

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
    lastTimeStamp,
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
    lastTimeStamp,
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
  };
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
