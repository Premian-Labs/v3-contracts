import {
  VxPremia__factory,
  VxPremiaProxy,
  VxPremiaProxy__factory,
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

  let proxyManager: string;
  let lzEndpoint: string;
  let proxy: VxPremiaProxy;
  let addresses: ContractAddresses;
  let addressesPath: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    proxyManager = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    lzEndpoint = '0x3c2269811836af69497E5F486A85D7316753cf62';
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    proxyManager = ethers.constants.AddressZero;
    lzEndpoint = ethers.constants.AddressZero;
    addresses = arbitrumGoerliAddresses;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  proxy = VxPremiaProxy__factory.connect(addresses.VxPremiaProxy, deployer);

  //////////////////////////

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    proxyManager,
    lzEndpoint,
    addresses.tokens.PREMIA,
    addresses.tokens.USDC,
    addresses.ExchangeHelper,
    addresses.VaultRegistryProxy,
  );
  await vxPremiaImpl.deployed();
  console.log(`VxPremia implementation : ${vxPremiaImpl.address}`);

  // Save new addresses
  addresses.VxPremiaImplementation = vxPremiaImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

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
