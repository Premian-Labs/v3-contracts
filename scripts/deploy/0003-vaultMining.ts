import {
  IERC20Metadata__factory,
  OptionPS__factory,
  OptionPSFactory__factory,
  OptionReward__factory,
  OptionRewardFactory__factory,
  PaymentSplitter__factory,
  Placeholder__factory,
  ProxyUpgradeableOwnable__factory,
  VaultMining__factory,
  VaultMiningProxy__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import {
  ContractKey,
  ContractType,
  getEvent,
  initialize,
  ONE_DAY,
  updateDeploymentMetadata,
} from '../utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  let { deployment } = await initialize(deployer);

  //////////////////////////

  const defaultOptionRewardFee = parseEther('0.05'); // 5%
  const feeReceiver = deployment.feeConverter.treasury.address;

  // OptionPSFactory Implementation
  const optionPSFactoryImpl = await new OptionPSFactory__factory(
    deployer,
  ).deploy();

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionPSFactoryImplementation,
    ContractType.Implementation,
    optionPSFactoryImpl,
    [],
    { logTxUrl: true },
  );

  // OptionPSFactory Proxy
  const optionPSFactoryProxyArgs = [optionPSFactoryImpl.address];

  const optionPSFactoryProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(optionPSFactoryProxyArgs[0]);

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionPSFactoryProxy,
    ContractType.Proxy,
    optionPSFactoryProxy,
    optionPSFactoryProxyArgs,
    { logTxUrl: true },
  );

  // OptionPS Implementation
  const optionPSImplementationArgs = [feeReceiver];

  const optionPSImplementation = await new OptionPS__factory(deployer).deploy(
    optionPSImplementationArgs[0],
  );

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionPSImplementation,
    ContractType.Implementation,
    optionPSImplementation,
    optionPSImplementationArgs,
    { logTxUrl: true },
  );

  // Set managed proxy implementation address
  await OptionPSFactory__factory.connect(
    optionPSFactoryProxy.address,
    deployer,
  ).setManagedProxyImplementation(optionPSImplementation.address);

  //////////////////////

  // OptionRewardFactory Implementation
  const optionRewardFactoryImplArgs = [
    defaultOptionRewardFee.toString(),
    feeReceiver,
  ];

  const optionRewardFactoryImpl = await new OptionRewardFactory__factory(
    deployer,
  ).deploy(optionRewardFactoryImplArgs[0], optionRewardFactoryImplArgs[1]);

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionRewardFactoryImplementation,
    ContractType.Implementation,
    optionRewardFactoryImpl,
    optionRewardFactoryImplArgs,
    { logTxUrl: true },
  );

  // OptionRewardFactory Proxy
  const optionRewardFactoryProxyArgs = [optionRewardFactoryImpl.address];

  const optionRewardFactoryProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(optionRewardFactoryProxyArgs[0]);

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionRewardFactoryProxy,
    ContractType.Proxy,
    optionRewardFactoryProxy,
    optionRewardFactoryProxyArgs,
    { logTxUrl: true },
  );

  // OptionReward Implementation
  const optionRewardImplementation = await new OptionReward__factory(
    deployer,
  ).deploy();

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionRewardImplementation,
    ContractType.Implementation,
    optionRewardImplementation,
    [],
    { logTxUrl: true },
  );

  await OptionRewardFactory__factory.connect(
    optionRewardFactoryProxy.address,
    deployer,
  ).setManagedProxyImplementation(optionRewardImplementation.address);

  //////////////////////////

  const rewardsPerYear = parseEther('1800000');

  const placeholder = await new Placeholder__factory(deployer).deploy();

  const vaultMiningProxyArgs = [placeholder.address, rewardsPerYear.toString()];
  const vaultMiningProxy = await new VaultMiningProxy__factory(deployer).deploy(
    vaultMiningProxyArgs[0],
    vaultMiningProxyArgs[1],
  );
  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.VaultMiningProxy,
    ContractType.Proxy,
    vaultMiningProxy,
    vaultMiningProxyArgs,
    { logTxUrl: true },
  );

  //////////////////////

  // PaymentSplitter Implementation
  const paymentSplitterImplArgs = [
    deployment.tokens.PREMIA,
    deployment.tokens.USDC,
    deployment.core.VxPremiaProxy.address,
    deployment.core.VaultMiningProxy.address,
  ];

  const paymentSplitterImpl = await new PaymentSplitter__factory(
    deployer,
  ).deploy(
    paymentSplitterImplArgs[0],
    paymentSplitterImplArgs[1],
    paymentSplitterImplArgs[2],
    paymentSplitterImplArgs[3],
  );

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.PaymentSplitterImplementation,
    ContractType.Implementation,
    paymentSplitterImpl,
    paymentSplitterImplArgs,
    { logTxUrl: true },
  );

  // PaymentSplitter Proxy
  const paymentSplitterProxyArgs = [paymentSplitterImpl.address];

  const paymentSplitterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(paymentSplitterProxyArgs[0]);

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.PaymentSplitterProxy,
    ContractType.Proxy,
    paymentSplitterProxy,
    paymentSplitterProxyArgs,
    { logTxUrl: true },
  );

  //////////////////////

  // Deploy PREMIA/USDC-C OptionPS

  const base = deployment.tokens.PREMIA;
  const quote = deployment.tokens.USDC;
  const isCall = true;

  let tx = await OptionPSFactory__factory.connect(
    deployment.core.OptionPSFactoryProxy.address,
    deployer,
  ).deployProxy({
    base,
    quote,
    isCall,
  });

  let baseSymbol = await IERC20Metadata__factory.connect(
    base,
    deployer,
  ).symbol();
  let quoteSymbol = await IERC20Metadata__factory.connect(
    quote,
    deployer,
  ).symbol();

  const name = `${baseSymbol}/${quoteSymbol}`;

  let event = await getEvent(tx, 'ProxyDeployed');

  let args = [
    deployment.core.OptionPSFactoryProxy.address,
    base,
    quote,
    isCall.toString(),
  ];

  const optionPSName = `${name}-${isCall ? 'C' : 'P'}`;

  deployment = await updateDeploymentMetadata(
    deployer,
    `optionPS.${optionPSName}`,
    ContractType.Proxy,
    event[0].args.proxy,
    args,
    { logTxUrl: true, txReceipt: await tx.wait() },
  );

  //////////////////////

  // Deploy PREMIA/USDC OptionReward

  const optionRewardKey = {
    option: deployment.optionPS[optionPSName].address,
    oracleAdapter: deployment.core.ChainlinkAdapterProxy.address,
    paymentSplitter: deployment.core.PaymentSplitterProxy.address,
    percentOfSpot: parseEther('0.55'),
    penalty: parseEther('0.75'),
    optionDuration: 30 * ONE_DAY,
    lockupDuration: 365 * ONE_DAY,
    claimDuration: 365 * ONE_DAY,
    fee: parseEther('0.1'),
    feeReceiver: deployment.feeConverter.dao.address,
  };

  tx = await OptionRewardFactory__factory.connect(
    deployment.core.OptionRewardFactoryProxy.address,
    deployer,
  )[
    'deployProxy((address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address))'
  ](optionRewardKey);

  event = await getEvent(tx, 'ProxyDeployed');

  args = [
    deployment.core.OptionRewardFactoryProxy.address,
    optionRewardKey.option,
    optionRewardKey.oracleAdapter,
    optionRewardKey.paymentSplitter,
    optionRewardKey.percentOfSpot.toString(),
    optionRewardKey.penalty.toString(),
    optionRewardKey.optionDuration.toString(),
    optionRewardKey.lockupDuration.toString(),
    optionRewardKey.claimDuration.toString(),
    optionRewardKey.fee.toString(),
    optionRewardKey.feeReceiver,
  ];

  deployment = await updateDeploymentMetadata(
    deployer,
    `optionReward.${name}`,
    ContractType.Proxy,
    event[0].args.proxy,
    args,
    { logTxUrl: true, txReceipt: await tx.wait() },
  );

  //////////////////////

  // Deploy VaultMining Implementation

  const vaultMiningImplementationArgs = [
    deployment.core.VaultRegistryProxy.address,
    deployment.tokens.PREMIA,
    deployment.core.VxPremiaProxy.address,
    deployment.optionReward['PREMIA/USDC'].address,
  ];

  const vaultMiningImplementation = await new VaultMining__factory(
    deployer,
  ).deploy(
    vaultMiningImplementationArgs[0],
    vaultMiningImplementationArgs[1],
    vaultMiningImplementationArgs[2],
    vaultMiningImplementationArgs[3],
  );

  deployment = await updateDeploymentMetadata(
    deployer,
    ContractKey.VaultMiningImplementation,
    ContractType.Implementation,
    vaultMiningImplementation,
    vaultMiningImplementationArgs,
    { logTxUrl: true },
  );

  // Upgrade implementation from placeholder to actual implementation
  await vaultMiningProxy.setImplementation(vaultMiningImplementation.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
