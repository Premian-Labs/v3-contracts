import { ethers } from 'hardhat';
import { OrderbookStream__factory } from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const orderbook = await new OrderbookStream__factory(deployer).deploy();

  console.log('Orderbook deployed to:', orderbook.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
