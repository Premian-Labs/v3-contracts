import {
  PoolFactory__factory,
  PoolFactoryProxy__factory,
} from '../../typechain';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import { ethers } from 'hardhat';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let premiaDiamond: string;
  let chainlinkAdapter: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

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
  await updateDeploymentInfos(
    deployer,
    ContractKey.PoolFactoryImplementation,
    ContractType.Implementation,
    implementation,
    args,
    true,
  );

  if (setImplementation) {
    const proxy = PoolFactoryProxy__factory.connect(
      deployment.PoolFactoryProxy.address,
      deployer,
    );
    await proxy.setImplementation(implementation.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
