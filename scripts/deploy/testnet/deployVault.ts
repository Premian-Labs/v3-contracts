import {
  UnderwriterVaultProxy__factory,
  VaultRegistry__factory,
} from '../../../typechain';
import goerliAddresses from '../../../utils/deployment/goerli.json';
import arbitrumGoerliAddresses from '../../../utils/deployment/arbitrumGoerli.json';
import { ethers } from 'hardhat';
import { ChainID, ContractAddresses } from '../../../utils/deployment/types';
import { keccak256 } from 'ethers/lib/utils';
import { OptionType, TradeSide } from '../../../utils/sdk/types';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  let addresses: ContractAddresses;

  if (chainId === ChainID.Goerli) {
    addresses = goerliAddresses;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
  } else {
    throw new Error('ChainId not implemented');
  }

  // Deploy UnderwriterVaultProxy
  const vaultType = keccak256('UnderwriterVault');
  const base = '';
  const quote = '';
  const oracleAdapter = '';
  const name = '';
  const symbol = '';
  const isCall = true;

  const underwriterVaultProxy = await new UnderwriterVaultProxy__factory(
    deployer,
  ).deploy(
    addresses.VaultRegistryProxy,
    base,
    quote,
    oracleAdapter,
    name,
    symbol,
    isCall,
  );

  await underwriterVaultProxy.deployed();
  console.log('UnderwriterVaultProxy: ', underwriterVaultProxy.address);

  // Register vault on the VaultRegistry
  const vaultRegistry = VaultRegistry__factory.connect(
    addresses.VaultRegistryProxy,
    deployer,
  );

  await vaultRegistry.addVault(
    underwriterVaultProxy.address,
    isCall ? quote : base,
    vaultType,
    TradeSide.SELL,
    isCall ? OptionType.CALL : OptionType.PUT,
  );
  await vaultRegistry.addSupportedTokenPairs(underwriterVaultProxy.address, [
    {
      base,
      quote,
      oracleAdapter,
    },
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
