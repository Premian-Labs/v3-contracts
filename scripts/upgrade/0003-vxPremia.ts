import {
  VxPremia__factory,
  VxPremiaProxy,
  VxPremiaProxy__factory,
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

  let proxyManager: string;
  let lzEndpoint: string;
  let proxy: VxPremiaProxy;
  let deployment: DeploymentInfos;
  let addressesPath: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    proxyManager = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    lzEndpoint = '0x3c2269811836af69497E5F486A85D7316753cf62';
    deployment = arbitrumDeployment;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    proxyManager = ethers.constants.AddressZero;
    lzEndpoint = ethers.constants.AddressZero;
    deployment = arbitrumGoerliDeployment;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  proxy = VxPremiaProxy__factory.connect(
    deployment.VxPremiaProxy.address,
    deployer,
  );

  //////////////////////////

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    proxyManager,
    lzEndpoint,
    deployment.tokens.PREMIA,
    deployment.tokens.USDC,
    deployment.ExchangeHelper,
    deployment.VaultRegistryProxy,
  );
  await vxPremiaImpl.deployed();
  console.log(`VxPremia implementation : ${vxPremiaImpl.address}`);

  // Save new addresses
  deployment.VxPremiaImplementation.address = vxPremiaImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(deployment, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(vxPremiaImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
