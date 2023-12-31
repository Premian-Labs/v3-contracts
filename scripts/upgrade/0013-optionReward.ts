import {
  OptionReward__factory,
  OptionRewardFactory__factory,
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
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const args: string[] = [];
  const implementation = await new OptionReward__factory(deployer).deploy();

  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionRewardImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = OptionRewardFactory__factory.connect(
    deployment.core.OptionRewardFactoryProxy.address,
    deployer,
  );

  const transaction =
    await proxy.populateTransaction.setManagedProxyImplementation(
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
