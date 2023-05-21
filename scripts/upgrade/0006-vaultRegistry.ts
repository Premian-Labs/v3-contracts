import {
  ProxyUpgradeableOwnable__factory,
  VaultRegistry__factory,
  VxPremiaProxy,
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

  let proxy: VxPremiaProxy;
  let addresses: ContractAddresses;
  let addressesPath: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.Goerli) {
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

  proxy = ProxyUpgradeableOwnable__factory.connect(
    addresses.VaultRegistryProxy,
    deployer,
  );

  //////////////////////////

  const vaultRegistryImpl = await new VaultRegistry__factory(deployer).deploy();

  console.log(`VaultRegistry implementation : ${vaultRegistryImpl.address}`);

  // Save new addresses
  addresses.VaultRegistryImplementation = vaultRegistryImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(vaultRegistryImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
