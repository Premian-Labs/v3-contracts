import { ethers } from 'hardhat';
import {
  ChainlinkAdapter__factory,
  ChainlinkAdapterProxy,
  ChainlinkAdapterProxy__factory,
} from '../../typechain';

import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import fs from 'fs';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let addresses: any;
  let addressesPath: string;
  let weth: string;
  let wbtc: string;
  let proxy: ChainlinkAdapterProxy;
  let setImplementation: boolean;

  if (chainId === 42161) {
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    // Arbitrum addresses
    weth = arbitrumAddresses.tokens.WETH;
    wbtc = arbitrumAddresses.tokens.WBTC;
    proxy = ChainlinkAdapterProxy__factory.connect(
      arbitrumAddresses.ChainlinkAdapterProxy,
      deployer,
    );
    setImplementation = false;
  } else if (chainId === 5) {
    addresses = goerliAddresses;
    addressesPath = 'utils/deployment/goerli.json';
    // Goerli addresses
    weth = goerliAddresses.tokens.WETH;
    wbtc = goerliAddresses.tokens.WBTC;
    proxy = ChainlinkAdapterProxy__factory.connect(
      goerliAddresses.ChainlinkAdapterProxy,
      deployer,
    );
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  //////////////////////////

  const chainlinkAdapterImpl = await new ChainlinkAdapter__factory(
    deployer,
  ).deploy(weth, wbtc);
  await chainlinkAdapterImpl.deployed();
  console.log(`ChainlinkAdapter impl : ${chainlinkAdapterImpl.address}`);

  // Save new addresses
  addresses.ChainlinkAdapterImplementation = chainlinkAdapterImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

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
