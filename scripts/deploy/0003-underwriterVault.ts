import {
  OrderbookStream__factory,
  UnderwriterVault__factory,
  UnderwriterVaultProxy__factory,
  VaultRegistry__factory,
  VxPremiaProxy,
} from '../../typechain';
import { ethers } from 'hardhat';
import { defaultAbiCoder, keccak256, parseEther } from 'ethers/lib/utils';
import { ChainID, ContractAddresses } from '../../utils/deployment/types';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
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

  // Set settings for vaultType if not yet set
  const settings = defaultAbiCoder.encode(
    [
      'uint256',
      'uint256',
      'uint256',
      'uint256',
      'uint256',
      'uint256',
      'uint256',
      'uint256',
      'uint256',
      'uint256',
    ],
    [
      parseEther('3'), // Alpha C Level
      parseEther('0.005'), // Hourly decay discount
      parseEther('1'), // Min C Level
      parseEther('1.2'), // Max C Level
      parseEther('3'), // Min DTE
      parseEther('30'), // Max DTE
      parseEther('0.1'), // Min Delta
      parseEther('0.7'), // Max Delta
      parseEther('0.05'), // Performance fee rate
      parseEther('0.02'), // Management fee rate
    ],
  );

  const vaultType = keccak256('UnderwriterVault');

  const vaultRegistry = VaultRegistry__factory.connect(
    addresses.VaultRegistryProxy,
    deployer,
  );
  const currentSettings = await vaultRegistry.getSettings(vaultType);
  if (currentSettings.length == 0) {
    await vaultRegistry.updateSettings(vaultType, settings);
  }

  // Deploy UnderwriterVault implementation

  const underwriterVaultImpl = await new UnderwriterVault__factory(
    deployer,
  ).deploy(
    addresses.VaultRegistryProxy,
    addresses.feeReceiver,
    addresses.VolatilityOracleProxy,
    addresses.PoolFactoryProxy,
    addresses.ERC20Router,
    addresses.VxPremiaProxy,
  );
  await underwriterVaultImpl.deployed();

  console.log(
    'UnderwriterVault implementation : ',
    underwriterVaultImpl.address,
  );

  // Set the implementation on the registry

  await vaultRegistry.setImplementation(
    vaultType,
    underwriterVaultImpl.address,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
