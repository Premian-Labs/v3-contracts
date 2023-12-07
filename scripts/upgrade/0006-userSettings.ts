import {
  ProxyUpgradeableOwnable__factory,
  UserSettings__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import {
  ContractKey,
  ContractType,
  initialize,
  proposeOrSendTransaction,
  updateDeploymentMetadata,
} from '../utils';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const implementation = await new UserSettings__factory(deployer).deploy();
  await updateDeploymentMetadata(
    deployer,
    ContractKey.UserSettingsImplementation,
    ContractType.Implementation,
    implementation,
    [],
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.core.UserSettingsProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposeToMultiSig ? proposer : deployer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
