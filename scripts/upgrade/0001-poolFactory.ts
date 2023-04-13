import {
  PoolFactory__factory,
  PoolFactoryProxy,
  PoolFactoryProxy__factory,
} from '../../typechain';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import { ContractAddresses } from '../../utils/deployment/types';
import fs from 'fs';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let addresses: ContractAddresses;
  let addressesPath: string;
  let weth: string;
  let premiaDiamond: string;
  let chainlinkAdapter: string;
  let proxy: PoolFactoryProxy;
  let setImplementation: boolean;

  if (chainId === 42161) {
    // Arbitrum
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === 5) {
    // Goerli
    addresses = goerliAddresses;
    addressesPath = 'utils/deployment/goerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  weth = addresses.tokens.WETH;
  premiaDiamond = addresses.PremiaDiamond;
  chainlinkAdapter = addresses.ChainlinkAdapterProxy;
  proxy = PoolFactoryProxy__factory.connect(
    addresses.PoolFactoryProxy,
    deployer,
  );

  //////////////////////////

  const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
    premiaDiamond,
    chainlinkAdapter,
    weth,
  );
  await poolFactoryImpl.deployed();
  console.log(`PoolFactory impl : ${poolFactoryImpl.address}`);

  // Save new addresses
  addresses.PoolFactoryImplementation = poolFactoryImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

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