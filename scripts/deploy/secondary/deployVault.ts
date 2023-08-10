import {
  IERC20Metadata__factory,
  UnderwriterVaultProxy__factory,
  VaultRegistry__factory,
} from '../../../typechain';
import arbitrumDeployment from '../../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../../utils/deployment/arbitrumGoerli.json';
import { ethers } from 'hardhat';
import {
  ChainID,
  ContractType,
  DeploymentInfos,
} from '../../../utils/deployment/types';
import { solidityKeccak256 } from 'ethers/lib/utils';
import { OptionType, TradeSide } from '../../../utils/sdk/types';
import { updateDeploymentInfos } from '../../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  let deployment: DeploymentInfos;
  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
  } else {
    throw new Error('ChainId not implemented');
  }
  //////////////////////////
  // Set those vars to the vault you want to deploy
  const base = deployment.tokens.WETH;
  const quote = deployment.tokens.USDC;
  const isCall = true;

  //////////////////////////

  let baseSymbol = await IERC20Metadata__factory.connect(
    base,
    deployer,
  ).symbol();
  let quoteSymbol = await IERC20Metadata__factory.connect(
    quote,
    deployer,
  ).symbol();

  if (chainId === ChainID.Arbitrum) {
    const USDCe = '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'.toLowerCase();
    if (base.toLowerCase() === USDCe) baseSymbol = 'USDCe';
    if (quote.toLowerCase() === USDCe) quoteSymbol = 'USDCe';
  }

  // Deploy UnderwriterVaultProxy
  const vaultType = solidityKeccak256(['string'], ['UnderwriterVault']);
  const oracleAdapter = deployment.ChainlinkAdapterProxy.address;
  const name = `Short Volatility - ${baseSymbol}/${quoteSymbol}-${
    isCall ? 'C' : 'P'
  }`;
  const symbol = `pSV-${baseSymbol}/${quoteSymbol}-${isCall ? 'C' : 'P'}`;

  const args = [
    deployment.VaultRegistryProxy.address,
    base,
    quote,
    oracleAdapter,
    name,
    symbol,
    isCall.toString(),
  ];
  const underwriterVaultProxy = await new UnderwriterVaultProxy__factory(
    deployer,
  ).deploy(
    args[0],
    args[1],
    args[2],
    args[3],
    args[4],
    args[5],
    args[6] === 'true',
  );
  await updateDeploymentInfos(
    deployer,
    `vaults.${symbol}`,
    ContractType.Proxy,
    underwriterVaultProxy,
    args,
    true,
  );

  // Register vault on the VaultRegistry
  const vaultRegistry = VaultRegistry__factory.connect(
    deployment.VaultRegistryProxy.address,
    deployer,
  );

  await vaultRegistry.addVault(
    underwriterVaultProxy.address,
    isCall ? base : quote,
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
