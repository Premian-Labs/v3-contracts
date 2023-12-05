import {
  PoolFactory__factory,
  PoolFactoryProxy__factory,
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

  let premiaDiamond = deployment.core.PremiaDiamond.address;

  //////////////////////////

  const args = [premiaDiamond, deployment.core.PoolFactoryDeployer.address];
  const implementation = await new PoolFactory__factory(deployer).deploy(
    args[0],
    args[1],
  );
  await updateDeploymentMetadata(
    deployer,
    ContractKey.PoolFactoryImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = PoolFactoryProxy__factory.connect(
    deployment.core.PoolFactoryProxy.address,
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
