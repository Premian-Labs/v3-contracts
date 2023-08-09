import {
  OptionMathExternal__factory,
  UnderwriterVault__factory,
  VaultRegistry__factory,
  VxPremiaProxy,
} from '../../typechain';
import { ethers } from 'hardhat';
import {
  defaultAbiCoder,
  parseEther,
  solidityKeccak256,
} from 'ethers/lib/utils';
import { ChainID, DeploymentInfos } from '../../utils/deployment/types';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let proxy: VxPremiaProxy;
  let deployment: DeploymentInfos;
  let addressesPath: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
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
  await optionMathExternal.deployed();

  console.log('OptionMathExternal : ', optionMathExternal.address);

  // Deploy UnderwriterVault implementation
  const underwriterVaultImpl = await new UnderwriterVault__factory(
    {
      'contracts/libraries/OptionMathExternal.sol:OptionMathExternal':
        optionMathExternal.address,
    },
    deployer,
  ).deploy(
    deployment.VaultRegistryProxy.address,
    deployment.feeReceiver,
    deployment.VolatilityOracleProxy.address,
    deployment.PoolFactoryProxy.address,
    deployment.ERC20Router.address,
    deployment.VxPremiaProxy.address,
    deployment.PremiaDiamond.address,
    deployment.VaultMiningProxy.address,
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
