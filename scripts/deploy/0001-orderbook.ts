import { OrderbookStream__factory } from '../../typechain';
import { ethers } from 'hardhat';
import { ContractKey, ContractType, updateDeploymentMetadata } from '../utils';

async function main() {
  const [deployer] = await ethers.getSigners();

  const orderbook = await new OrderbookStream__factory(deployer).deploy();
  await updateDeploymentMetadata(
    deployer,
    ContractKey.OrderbookStream,
    ContractType.Standalone,
    orderbook,
    [],
    { logTxUrl: true },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
