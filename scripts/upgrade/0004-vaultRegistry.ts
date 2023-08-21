import {
  ProxyUpgradeableOwnable__factory,
  VaultRegistry__factory,
} from '../../typechain';
import { ContractKey, ContractType } from '../../utils/deployment/types';
import { ethers } from 'hardhat';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const implementation = await new VaultRegistry__factory(deployer).deploy();
  await updateDeploymentMetadata(
    deployer,
    ContractKey.VaultRegistryImplementation,
    ContractType.Implementation,
    implementation,
    [],
    true,
  );

  const proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.core.VaultRegistryProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
