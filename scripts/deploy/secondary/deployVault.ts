import {
  IERC20Metadata__factory,
  UnderwriterVaultProxy__factory,
  VaultRegistry__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { ChainID, ContractType } from '../../../utils/deployment/types';
import {
  defaultAbiCoder,
  parseEther,
  solidityKeccak256,
} from 'ethers/lib/utils';
import { OptionType, TradeSide } from '../../../utils/sdk/types';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { network, deployment, proposeToMultiSig } = await initialize(deployer);

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

  if (network.chainId === ChainID.Arbitrum) {
    const USDCe = '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'.toLowerCase();
    if (base.toLowerCase() === USDCe) baseSymbol = 'USDCe';
    if (quote.toLowerCase() === USDCe) quoteSymbol = 'USDCe';
  }

  // Deploy UnderwriterVaultProxy
  const vaultType = solidityKeccak256(['string'], ['UnderwriterVault']);
  const oracleAdapter = deployment.core.ChainlinkAdapterProxy.address;
  const name = `Short Volatility - ${baseSymbol}/${quoteSymbol}-${
    isCall ? 'C' : 'P'
  }`;
  const symbol = `pSV-${baseSymbol}/${quoteSymbol}-${isCall ? 'C' : 'P'}`;

  const settings = defaultAbiCoder.encode(
    ['uint256[]'],
    [
      [
        parseEther('3'), // Alpha C Level
        parseEther('0.005'), // Hourly decay discount
        parseEther('1'), // Min C Level
        parseEther('1.35'), // Max C Level
        parseEther('3'), // Min DTE
        parseEther('30'), // Max DTE
        parseEther('0.2'), // Min Delta
        parseEther('0.7'), // Max Delta
        parseEther('0.2'), // Performance fee rate
        parseEther('0.02'), // Management fee rate
      ],
    ],
  );

  const args = [
    deployment.core.VaultRegistryProxy.address,
    base,
    quote,
    oracleAdapter,
    name,
    symbol,
    isCall.toString(),
    settings,
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
    args[7],
  );

  await updateDeploymentMetadata(
    deployer,
    `vaults.${symbol}`,
    ContractType.Proxy,
    underwriterVaultProxy,
    args,
    { logTxUrl: true },
  );

  // Register vault on the VaultRegistry
  const vaultRegistry = VaultRegistry__factory.connect(
    deployment.core.VaultRegistryProxy.address,
    deployer,
  );

  const addVaultTx = await vaultRegistry.populateTransaction.addVault(
    underwriterVaultProxy.address,
    isCall ? base : quote,
    vaultType,
    TradeSide.SELL,
    isCall ? OptionType.CALL : OptionType.PUT,
  );

  const addSupportedTokenPairsTx =
    await vaultRegistry.populateTransaction.addSupportedTokenPairs(
      underwriterVaultProxy.address,
      [
        {
          base,
          quote,
          oracleAdapter,
        },
      ],
    );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposeToMultiSig ? proposer : deployer,
    [addVaultTx, addSupportedTokenPairsTx],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
