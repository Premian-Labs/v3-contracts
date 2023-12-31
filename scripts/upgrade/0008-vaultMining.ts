import {
  VaultMining__factory,
  VaultMiningProxy__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import {
  ContractKey,
  ContractType,
  initialize,
  proposeOrSendTransaction,
  updateDeploymentMetadata,
} from '../utils';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  let { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const args = [
    deployment.core.VaultRegistryProxy.address,
    deployment.tokens.PREMIA,
    deployment.core.VxPremiaProxy.address,
    deployment.optionReward['PREMIA/USDC'].address,
  ];
  const implementation = await new VaultMining__factory(deployer).deploy(
    args[0],
    args[1],
    args[2],
    args[3],
  );
  await updateDeploymentMetadata(
    deployer,
    ContractKey.VaultMiningImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = VaultMiningProxy__factory.connect(
    deployment.core.VaultMiningProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
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
