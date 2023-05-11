import {
  ChainlinkAdapterProxy,
  UniswapV3ChainlinkAdapter__factory,
  UniswapV3ChainlinkAdapterProxy__factory,
} from '../../typechain';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import arbitrumGoerliAddresses from '../../utils/deployment/arbitrumGoerli.json';
import { ChainID, ContractAddresses } from '../../utils/deployment/types';
import fs from 'fs';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let addresses: ContractAddresses;
  let addressesPath: string;
  let weth: string;
  let proxy: ChainlinkAdapterProxy;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    // Arbitrum
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.Goerli) {
    // Goerli
    addresses = goerliAddresses;
    addressesPath = 'utils/deployment/goerli.json';
    setImplementation = true;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  weth = addresses.tokens.WETH;
  proxy = UniswapV3ChainlinkAdapterProxy__factory.connect(
    addresses.ChainlinkAdapterProxy,
    deployer,
  );

  //////////////////////////

  const uniswapV3ChainlinkAdapterImpl =
    await new UniswapV3ChainlinkAdapter__factory(deployer).deploy(
      addresses.ChainlinkAdapterProxy,
      addresses.UniswapV3AdapterProxy,
      weth,
    );
  await uniswapV3ChainlinkAdapterImpl.deployed();
  console.log(
    `uniswapV3ChainlinkAdapter impl : ${uniswapV3ChainlinkAdapterImpl.address}`,
  );

  // Save new addresses
  addresses.UniswapV3ChainlinkAdapterImplementation =
    uniswapV3ChainlinkAdapterImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(uniswapV3ChainlinkAdapterImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
