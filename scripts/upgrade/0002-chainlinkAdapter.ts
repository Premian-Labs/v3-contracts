import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
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
  let weth: string;
  let wbtc: string;
  let proxy: ProxyUpgradeableOwnable;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    // Arbitrum
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

  weth = deployment.tokens.WETH;
  wbtc = deployment.tokens.WBTC;
  proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.ChainlinkAdapterProxy.address,
    deployer,
  );

  //////////////////////////

  const chainlinkAdapterImpl = await new ChainlinkAdapter__factory(
    deployer,
  ).deploy(weth, wbtc);
  await chainlinkAdapterImpl.deployed();
  console.log(`ChainlinkAdapter impl : ${chainlinkAdapterImpl.address}`);

  // Save new addresses
  deployment.ChainlinkAdapterImplementation.address =
    chainlinkAdapterImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(deployment, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(chainlinkAdapterImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
