import {
  DualMining__factory,
  DualMiningManager__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { ChainID, ContractKey, ContractType } from '../utils/deployment/types';
import {
  initialize,
  updateDeploymentMetadata,
} from '../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, network } = await initialize(deployer);

  const dualMiningImplementation = await new DualMining__factory(
    deployer,
  ).deploy(deployment.core.VaultMiningProxy.address);

  await updateDeploymentMetadata(
    deployer,
    ContractKey.DualMiningImplementation,
    ContractType.Implementation,
    dualMiningImplementation,
    [deployment.core.VaultMiningProxy.address],
    { logTxUrl: true },
  );

  const dualMiningManager = await new DualMiningManager__factory(
    deployer,
  ).deploy(dualMiningImplementation.address);

  await updateDeploymentMetadata(
    deployer,
    ContractKey.DualMiningManager,
    ContractType.Standalone,
    dualMiningManager,
    [dualMiningImplementation.address],
    { logTxUrl: true },
  );

  if (network.chainId === ChainID.Arbitrum) {
    await dualMiningManager.transferOwnership(deployment.addresses.treasury);

    const tx = await dualMiningManager.populateTransaction.acceptOwnership();
    await proposeOrSendTransaction(
      true,
      deployment.addresses.treasury,
      proposer,
      [tx],
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
