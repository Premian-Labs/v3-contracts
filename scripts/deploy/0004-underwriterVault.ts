import {
  OptionMathExternal__factory,
  UnderwriterVault__factory,
  VaultRegistry__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import {
  defaultAbiCoder,
  parseEther,
  solidityKeccak256,
} from 'ethers/lib/utils';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
  } else {
    throw new Error('ChainId not implemented');
  }

  // Set settings for vaultType if not yet set
  const settings = defaultAbiCoder.encode(
    ['uint256[]'],
    [
      [
        parseEther('3'), // Alpha C Level
        parseEther('0.005'), // Hourly decay discount
        parseEther('1'), // Min C Level
        parseEther('1.2'), // Max C Level
        parseEther('3'), // Min DTE
        parseEther('30'), // Max DTE
        parseEther('0.1'), // Min Delta
        parseEther('0.7'), // Max Delta
        parseEther('0.2'), // Performance fee rate
        parseEther('0.02'), // Management fee rate
      ],
    ],
  );

  const vaultType = solidityKeccak256(['string'], ['UnderwriterVault']);

  const vaultRegistry = VaultRegistry__factory.connect(
    deployment.VaultRegistryProxy.address,
    deployer,
  );
  const currentSettings = await vaultRegistry.getSettings(vaultType);
  if (currentSettings == '0x') {
    await vaultRegistry.updateSettings(vaultType, settings);
  }

  const optionMathExternal = await new OptionMathExternal__factory(
    deployer,
  ).deploy();
  await updateDeploymentInfos(
    deployer,
    ContractKey.OptionMathExternal,
    ContractType.Standalone,
    optionMathExternal,
    [],
    true,
  );

  //////////////////////////

  // Deploy UnderwriterVault implementation
  const underwriterVaultImplArgs = [
    deployment.VaultRegistryProxy.address,
    deployment.feeConverter.insuranceFund.address,
    deployment.VolatilityOracleProxy.address,
    deployment.PoolFactoryProxy.address,
    deployment.ERC20Router.address,
    deployment.VxPremiaProxy.address,
    deployment.PremiaDiamond.address,
    deployment.VaultMiningProxy.address,
  ];

  const underwriterVaultImpl = await new UnderwriterVault__factory(
    {
      'contracts/libraries/OptionMathExternal.sol:OptionMathExternal':
        optionMathExternal.address,
    },
    deployer,
  ).deploy(
    underwriterVaultImplArgs[0],
    underwriterVaultImplArgs[1],
    underwriterVaultImplArgs[2],
    underwriterVaultImplArgs[3],
    underwriterVaultImplArgs[4],
    underwriterVaultImplArgs[5],
    underwriterVaultImplArgs[6],
    underwriterVaultImplArgs[7],
  );

  await updateDeploymentInfos(
    deployer,
    ContractKey.UnderwriterVaultImplementation,
    ContractType.Implementation,
    underwriterVaultImpl,
    underwriterVaultImplArgs,
    true,
  );

  //////////////////////////

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
