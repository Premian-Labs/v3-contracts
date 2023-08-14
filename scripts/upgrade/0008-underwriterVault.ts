import {
  UnderwriterVault__factory,
  VaultRegistry__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { solidityKeccak256 } from 'ethers/lib/utils';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let proposeToMultiSig: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    proposeToMultiSig = true;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    proposeToMultiSig = false;
  } else {
    throw new Error('ChainId not implemented');
  }

  const vaultType = solidityKeccak256(['string'], ['UnderwriterVault']);

  const vaultRegistry = VaultRegistry__factory.connect(
    deployment.VaultRegistryProxy.address,
    deployer,
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
        deployment.OptionMathExternal.address,
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
  const transaction = await vaultRegistry.populateTransaction.setImplementation(
    vaultType,
    underwriterVaultImpl.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.treasury,
    proposer,
    [{ transaction, isCall: true }],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
