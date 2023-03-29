import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ChainlinkAdapter__factory,
  ChainlinkAdapterProxy__factory,
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
  OptionMathMock,
  OptionMathMock__factory,
  OracleAdapter,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy,
  UnderwriterVaultProxy__factory,
  VolatilityOracle,
  VolatilityOracle__factory,
  VolatilityOracleMock,
  VolatilityOracleMock__factory,
} from '../../../../typechain';
import { PoolUtil } from '../../../../utils/PoolUtil';
import { getValidMaturity, latest, ONE_DAY } from '../../../../utils/time';
import { PoolKey } from '../../../../utils/sdk/types';
import { feeds, tokens } from '../../../../utils/addresses';
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

export let oracleAdapter: OracleAdapter;
export let volOracle: VolatilityOracle;
export let volOracleProxy: ProxyUpgradeableOwnable;

export const log = true;

export let startTime: number;
export let spot: number;
export let minMaturity: number;
export let maxMaturity: number;

export async function deposit(
  vault: UnderwriterVaultMock,
  lp: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  assets: number,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const assetAmount = parseUnits(assets.toString(), await token.decimals());

  await token.connect(lp).approve(vault.address, assetAmount);
  await vault.connect(lp).deposit(assetAmount, lp.address);
}

export async function mint(
  vault: UnderwriterVaultMock,
  lp: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  shares: number,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const shareAmount = parseEther(shares.toString());

  // Get the amount needed to be approved for transfer
  const assetAmount = await vault.previewMint(shareAmount);

  // Approve transfer of assets
  await token.connect(lp).approve(vault.address, assetAmount);

  // Mint shares
  await vault.connect(lp).mint(shareAmount, lp.address);
}

export async function withdraw(
  vault: UnderwriterVaultMock,
  lp: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  assets: number,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const assetAmount = parseUnits(assets.toString(), await token.decimals());

  // Approve amount for the LP to withdraw
  await token.connect(lp).approve(vault.address, assetAmount);

  // Withdraw funds
  await vault.connect(lp).withdraw(assetAmount, lp.address, lp.address);
}

export async function redeem(
  vault: UnderwriterVaultMock,
  lp: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  shares: number,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const shareAmount = parseUnits(shares.toString(), await token.decimals());

  // Get the amount needed to be approved for transfer
  const assetAmount = await vault.previewRedeem(shareAmount);

  // Approve amount for the LP to withdraw
  await token.connect(lp).approve(vault.address, assetAmount);

  // Withdraw funds
  await vault.connect(lp).redeem(shareAmount, lp.address, lp.address);
}

export async function trade(
  vault: UnderwriterVaultMock,
  trader: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  strike: number,
  maturity: number,
  size: number,
) {
  const isCall = await vault.isCall();
  const token = isCall ? base : quote;
  const strikeBN = parseEther(strike.toString());
  const tradeSize = parseEther(size.toString());

  // Check that the premium has been transferred
  const quoteOutput = await vault.getTradeQuote(
    strikeBN,
    maturity,
    isCall,
    tradeSize,
    true,
  );
  const totalPremium = quoteOutput[1];
  const collateral = parseUnits(size.toString(), await token.decimals());

  // Approve amount for trader to trade with
  await token
    .connect(trader)
    .approve(vault.address, totalPremium.add(collateral));

  // Execute trade
  await vault
    .connect(trader)
    .trade(strikeBN, maturity, isCall, tradeSize, true);
}

export async function createPool(
  strike: BigNumber,
  maturity: number,
  isCall: boolean,
  deployer: SignerWithAddress,
  base: ERC20Mock,
  quote: ERC20Mock,
  oracleAdapter: OracleAdapter,
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

  const implementation = await new ChainlinkAdapter__factory(deployer).deploy(
    tokens.WETH.address,
    tokens.WBTC.address,
  );

  await implementation.deployed();

  const proxy = await new ChainlinkAdapterProxy__factory(deployer).deploy(
    implementation.address,
  );

  await proxy.deployed();

  const oracleAdapter = ChainlinkAdapter__factory.connect(
    proxy.address,
    deployer,
  );

  await oracleAdapter.batchRegisterFeedMappings(feeds);

  if (log)
    console.log(`Mock oracleAdapter Implementation : ${oracleAdapter.address}`);

  //=====================================================================================
  // Volatility Oracle setup

  const impl = await new VolatilityOracle__factory(deployer).deploy();

  volOracleProxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
    impl.address,
  );

  volOracle = VolatilityOracle__factory.connect(
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
  const riskFreeRate = parseEther('0.01');

  await volOracle
    .connect(deployer)
    .updateParams(
      [base.address],
      [tauHex],
      [thetaHex],
      [psiHex],
      [rhoHex],
      riskFreeRate,
    );

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
