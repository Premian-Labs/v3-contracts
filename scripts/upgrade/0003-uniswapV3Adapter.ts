import {
  ChainlinkAdapterProxy,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
} from '../../typechain';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import arbitrumGoerliAddresses from '../../utils/deployment/arbitrumGoerli.json';
import { ChainID, ContractAddresses } from '../../utils/deployment/types';
import fs from 'fs';
import { ethers } from 'hardhat';
import { UNISWAP_V3_FACTORY } from '../../utils/addresses';

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
  proxy = UniswapV3AdapterProxy__factory.connect(
    addresses.UniswapV3AdapterProxy,
    deployer,
  );

  //////////////////////////

  const gasPerCardinality = 22250;
  const gasPerPool = 30000;

  const uniswapV3AdapterImpl = await new UniswapV3Adapter__factory(
    deployer,
  ).deploy(UNISWAP_V3_FACTORY, weth, gasPerCardinality, gasPerPool);
  await uniswapV3AdapterImpl.deployed();
  console.log(`UniswapV3Adapter impl : ${uniswapV3AdapterImpl.address}`);

  // Save new addresses
  addresses.UniswapV3AdapterImplementation = uniswapV3AdapterImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(uniswapV3AdapterImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
