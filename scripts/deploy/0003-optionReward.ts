import {
  OptionPS__factory,
  OptionPSFactory__factory,
  OptionReward__factory,
  OptionRewardFactory__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { ContractKey, ContractType } from '../../utils/deployment/types';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../utils/deployment/deployment';
import { parseEther } from 'ethers/lib/utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  const defaultOptionRewardFee = parseEther('0.05'); // 5%
  const feeReceiver = deployment.feeConverter.treasury.address;

  // OptionPSFactory Implementation
  const optionPSFactoryImpl = await new OptionPSFactory__factory(
    deployer,
  ).deploy();

  await updateDeploymentMetadata(
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

  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionPSFactoryProxy,
    ContractType.Proxy,
    optionPSFactoryProxy,
    [],
    { logTxUrl: true },
  );

  // OptionPS Implementation
  const optionPSImplementationArgs = [feeReceiver];

  const optionPSImplementation = await new OptionPS__factory(deployer).deploy(
    optionPSImplementationArgs[0],
  );

  await updateDeploymentMetadata(
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
  const optionRewardFactoryImpl = await new OptionRewardFactory__factory(
    deployer,
  ).deploy(defaultOptionRewardFee, feeReceiver);

  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionRewardFactoryImplementation,
    ContractType.Implementation,
    optionRewardFactoryImpl,
    [],
    { logTxUrl: true },
  );

  // OptionRewardFactory Proxy
  const optionRewardFactoryProxyArgs = [optionRewardFactoryImpl.address];

  const optionRewardFactoryProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(optionRewardFactoryProxyArgs[0]);

  await updateDeploymentMetadata(
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

  await updateDeploymentMetadata(
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
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
