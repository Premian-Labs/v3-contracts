import {
  PoolFactory__factory,
  PoolFactoryProxy__factory,
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

  let premiaDiamond: string;
  let chainlinkAdapter: string;

  premiaDiamond = deployment.PremiaDiamond.address;
  chainlinkAdapter = deployment.ChainlinkAdapterProxy.address;

  //////////////////////////

  const args = [
    premiaDiamond,
    chainlinkAdapter,
    deployment.tokens.WETH,
    deployment.PoolFactoryDeployer.address,
  ];
  const implementation = await new PoolFactory__factory(deployer).deploy(
    args[0],
    args[1],
    args[2],
    args[3],
  );
  await updateDeploymentMetadata(
    deployer,
    ContractKey.PoolFactoryImplementation,
    ContractType.Implementation,
    implementation,
    args,
    true,
  );

  const proxy = PoolFactoryProxy__factory.connect(
    deployment.PoolFactoryProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.treasury,
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
