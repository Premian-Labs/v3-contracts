import { OrderbookStream__factory } from '../../typechain';
import { ethers } from 'hardhat';
import { updateDeploymentMetadata } from '../../utils/deployment/deployment';
import { ContractKey, ContractType } from '../../utils/deployment/types';

async function main() {
  const [deployer] = await ethers.getSigners();

  const orderbook = await new OrderbookStream__factory(deployer).deploy();
  await updateDeploymentMetadata(
    deployer,
    ContractKey.OrderbookStream,
    ContractType.Standalone,
    orderbook,
    [],
    true,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
