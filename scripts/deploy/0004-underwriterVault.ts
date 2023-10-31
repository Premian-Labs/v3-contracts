import {
  OptionMathExternal__factory,
  UnderwriterVault__factory,
  VaultRegistry__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { solidityKeccak256 } from 'ethers/lib/utils';
import { ContractKey, ContractType } from '../../utils/deployment/types';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  const vaultType = solidityKeccak256(['string'], ['UnderwriterVault']);

  const vaultRegistry = VaultRegistry__factory.connect(
    deployment.core.VaultRegistryProxy.address,
    deployer,
  );

  const optionMathExternal = await new OptionMathExternal__factory(
    deployer,
  ).deploy();
  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionMathExternal,
    ContractType.Standalone,
    optionMathExternal,
    [],
    { logTxUrl: true },
  );

  //////////////////////////

  // Deploy UnderwriterVault implementation
  const underwriterVaultImplArgs = [
    deployment.core.VaultRegistryProxy.address,
    deployment.feeConverter.insuranceFund.address,
    deployment.core.VolatilityOracleProxy.address,
    deployment.core.PoolFactoryProxy.address,
    deployment.core.ERC20Router.address,
    deployment.core.VxPremiaProxy.address,
    deployment.core.PremiaDiamond.address,
    deployment.core.VaultMiningProxy.address,
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

  await updateDeploymentMetadata(
    deployer,
    ContractKey.UnderwriterVaultImplementation,
    ContractType.Implementation,
    underwriterVaultImpl,
    underwriterVaultImplArgs,
    { logTxUrl: true },
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
