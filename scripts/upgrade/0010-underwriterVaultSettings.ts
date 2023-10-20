import { VaultRegistry__factory } from '../../typechain';
import { ethers } from 'hardhat';
import {
  defaultAbiCoder,
  parseEther,
  solidityKeccak256,
} from 'ethers/lib/utils';
import { initialize } from '../../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const vaultType = solidityKeccak256(['string'], ['UnderwriterVault']);

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

  //////////////////////////

  const vaultRegistry = VaultRegistry__factory.connect(
    deployment.core.VaultRegistryProxy.address,
    deployer,
  );

  // Set the implementation on the registry
  const transaction = await vaultRegistry.populateTransaction.updateSettings(
    vaultType,
    settings,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposeToMultiSig ? proposer : deployer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
