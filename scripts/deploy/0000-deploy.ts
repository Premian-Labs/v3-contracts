import { ethers } from 'hardhat';
import { PoolUtil } from '../PoolUtil';

async function main() {
  const [deployer] = await ethers.getSigners();

  await PoolUtil.deploy(deployer, true);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
