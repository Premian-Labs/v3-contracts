import {
  PoolFactory__factory,
  PoolFactoryProxy,
  PoolFactoryProxy__factory,
} from '../../typechain';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import { ChainID, DeploymentInfos } from '../../utils/deployment/types';
import fs from 'fs';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let addressesPath: string;
  let premiaDiamond: string;
  let chainlinkAdapter: string;
  let proxy: PoolFactoryProxy;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  premiaDiamond = deployment.PremiaDiamond.address;
  chainlinkAdapter = deployment.ChainlinkAdapterProxy.address;
  proxy = PoolFactoryProxy__factory.connect(
    deployment.PoolFactoryProxy.address,
    deployer,
  );

  //////////////////////////

  const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
    premiaDiamond,
    chainlinkAdapter,
    deployment.tokens.WETH,
    deployment.PoolFactoryDeployer.address,
  );
  await poolFactoryImpl.deployed();
  console.log(`PoolFactory impl : ${poolFactoryImpl.address}`);

  // Save new addresses
  deployment.PoolFactoryImplementation.address = poolFactoryImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(deployment, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(poolFactoryImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
