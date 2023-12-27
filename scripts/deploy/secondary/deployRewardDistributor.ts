import {
  IERC20Metadata__factory,
  RewardDistributor__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import {
  ContractType,
  initialize,
  updateDeploymentMetadata,
} from '../../utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  const token = deployment.tokens['ARB'];

  const symbol = await IERC20Metadata__factory.connect(
    token,
    deployer,
  ).symbol();

  const rewardDistributor = await new RewardDistributor__factory(
    deployer,
  ).deploy(deployment.tokens['ARB']);

  await updateDeploymentMetadata(
    deployer,
    `rewardDistributor.${symbol}`,
    ContractType.Standalone,
    rewardDistributor,
    [token],
    { logTxUrl: true, verification: { enableVerification: true } },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
