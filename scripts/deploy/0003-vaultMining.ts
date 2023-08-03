import {
  VaultMining__factory,
  VaultMiningProxy__factory,
  VxPremiaProxy,
} from '../../typechain';
import { ethers } from 'hardhat';
import { ChainID, ContractAddresses } from '../../utils/deployment/types';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliAddresses from '../../utils/deployment/arbitrumGoerli.json';

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
  } else if (chainId === ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  // ToDo : Deploy OptionReward contract

  const vaultMiningImplementation = await new VaultMining__factory(
    deployer,
  ).deploy(
    addresses.VaultRegistryProxy,
    addresses.tokens.PREMIA,
    addresses.VxPremiaProxy,
    addresses.optionReward['PREMIA/USDC'],
  );

  await vaultMiningImplementation.deployed();

  console.log(`VaultMining impl : ${vaultMiningImplementation.address}`);

  const rewardsPerYear = 0; // ToDo : Set
  const vaultMiningProxy = await new VaultMiningProxy__factory(deployer).deploy(
    vaultMiningImplementation.address,
    rewardsPerYear,
  );
  await vaultMiningProxy.deployed();

  console.log(`VaultMining proxy : ${vaultMiningProxy.address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
