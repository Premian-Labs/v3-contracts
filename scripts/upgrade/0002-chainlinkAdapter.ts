import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
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
  let wbtc: string;
  let proxy: ProxyUpgradeableOwnable;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    // Arbitrum
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  weth = addresses.tokens.WETH;
  wbtc = addresses.tokens.WBTC;
  proxy = ProxyUpgradeableOwnable__factory.connect(
    addresses.ChainlinkAdapterProxy,
    deployer,
  );

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
