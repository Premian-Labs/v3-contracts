import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy,
  UnderwriterVaultProxy__factory,
  VolatilityOracleMock,
  VolatilityOracleMock__factory,
} from '../../../typechain';
import { BigNumberish } from 'ethers';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { ethers } from 'hardhat';
import { getContractAddress, parseEther, parseUnits } from 'ethers/lib/utils';

export let deployer: SignerWithAddress;
export let caller: SignerWithAddress;
export let receiver: SignerWithAddress;
export let lp: SignerWithAddress;
export let trader: SignerWithAddress;

export let vaultImpl: UnderwriterVaultMock;
export let vaultProxy: UnderwriterVaultProxy;
export let vault: UnderwriterVaultMock;

export interface Clevel {
  minClevel: BigNumberish;
  maxClevel: BigNumberish;
  alphaClevel: BigNumberish;
  hourlyDecayDiscount: BigNumberish;
}

export interface TradeBounds {
  maxDTE: BigNumberish;
  minDTE: BigNumberish;
  minDelta: BigNumberish;
  maxDelta: BigNumberish;
}

export let base: ERC20Mock;
export let quote: ERC20Mock;
export let long: ERC20Mock;
export let short: ERC20Mock;

export let oracleAdapter: MockContract;
export let factory: MockContract;
export let volOracle: VolatilityOracleMock;
export let volOracleProxy: ProxyUpgradeableOwnable;

export const log = true;
export async function vaultSetup() {
  [deployer, caller, receiver, lp, trader] = await ethers.getSigners();

  base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
  quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
  long = await new ERC20Mock__factory(deployer).deploy('Long', 18);
  short = await new ERC20Mock__factory(deployer).deploy('Short', 18);

  await base.deployed();
  await quote.deployed();
  await long.deployed();
  await short.deployed();

  // Hydrate all accounts with WETH and USDC
  await base.mint(deployer.address, parseEther('1000'));
  await quote.mint(deployer.address, parseEther('1000000'));

  await base.mint(caller.address, parseEther('1000'));
  await quote.mint(caller.address, parseEther('1000000'));

  await base.mint(receiver.address, parseEther('1000'));
  await quote.mint(receiver.address, parseEther('1000000'));

  await base.mint(lp.address, parseEther('1000'));
  await quote.mint(lp.address, parseEther('1000000'));

  await base.mint(trader.address, parseEther('1000'));
  await quote.mint(trader.address, parseEther('1000000'));

  // Mock Oracle Adapter setup
  oracleAdapter = await deployMockContract(deployer, [
    'function quote(address, address) external view returns (uint256)',
    'function quoteFrom(address, address, uint256) external view returns (uint256)',
  ]);

  await oracleAdapter.mock.quote.returns(parseUnits('1500', 8));

  if (log)
    console.log(`Mock oracelAdapter Implementation : ${oracleAdapter.address}`);

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

  // Mock Pool setup
  const transactionCount = await deployer.getTransactionCount();
  const poolAddress = getContractAddress({
    from: deployer.address,
    nonce: transactionCount,
  });

  // Mock Option Pool setup
  factory = await deployMockContract(deployer, [
    'function getPoolAddress () external view returns (address)',
  ]);
  await factory.mock.getPoolAddress.returns(poolAddress);
  if (log) console.log(`Mock Pool Address : ${poolAddress}`);

  // Mock Vault setup
  vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
    volOracle.address,
    factory.address,
  );
  await vaultImpl.deployed();
  if (log)
    console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

  const _cLevelParams: Clevel = {
    minClevel: parseEther('1.0'),
    maxClevel: parseEther('1.2'),
    alphaClevel: parseEther('3.0'),
    hourlyDecayDiscount: parseEther('0.005'),
  };

  const _tradeBounds: TradeBounds = {
    maxDTE: parseEther('30'),
    minDTE: parseEther('3'),
    minDelta: parseEther('0.1'),
    maxDelta: parseEther('0.7'),
  };

  const timeStamp = new Date().getTime();
  // Vault Proxy setup
  vaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
    vaultImpl.address,
    base.address,
    quote.address,
    oracleAdapter.address,
    'WETH Vault',
    'WETH',
    true,
    _cLevelParams,
    _tradeBounds,
    0,
    timeStamp,
  );
  await vaultProxy.deployed();
  vault = UnderwriterVaultMock__factory.connect(vaultProxy.address, deployer);
  if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);

  return { base, quote, vault, volOracle, oracleAdapter };
}
