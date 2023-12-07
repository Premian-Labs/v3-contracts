import { OptionPS__factory, OptionPSFactory__factory } from '../../typechain';
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

  const feeReceiver = deployment.feeConverter.treasury.address;

  const args = [feeReceiver];

  const implementation = await new OptionPS__factory(deployer).deploy(args[0]);

  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionPSImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = OptionPSFactory__factory.connect(
    deployment.core.OptionPSFactoryProxy.address,
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
