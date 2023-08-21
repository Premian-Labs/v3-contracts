import {
  VaultMining__factory,
  VaultMiningProxy__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { ContractKey, ContractType } from '../../utils/deployment/types';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  // ToDo : Deploy OptionReward contract

  //////////////////////////

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

  await updateDeploymentMetadata(
    deployer,
    ContractKey.VaultMiningImplementation,
    ContractType.Implementation,
    vaultMiningImplementation,
    vaultMiningImplementationArgs,
    { logTxUrl: true },
  );

  //////////////////////////

  const rewardsPerYear = 0; // ToDo : Set

  const vaultMiningProxyArgs = [
    vaultMiningImplementation.address,
    rewardsPerYear.toString(),
  ];
  const vaultMiningProxy = await new VaultMiningProxy__factory(deployer).deploy(
    vaultMiningProxyArgs[0],
    vaultMiningProxyArgs[1],
  );
  await updateDeploymentMetadata(
    deployer,
    ContractKey.VaultMiningProxy,
    ContractType.Proxy,
    vaultMiningProxy,
    vaultMiningProxyArgs,
    { logTxUrl: true },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
