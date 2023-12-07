import { OptionMathExternal__factory } from '../../typechain';
import { ethers } from 'hardhat';
import { ContractKey, ContractType, updateDeploymentMetadata } from '../utils';

async function main() {
  const [deployer] = await ethers.getSigners();

  //////////////////////////

  const optionMath = await new OptionMathExternal__factory(deployer).deploy();

  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionMathExternal,
    ContractType.Standalone,
    optionMath.address,
    [],
    { logTxUrl: true, verification: { enableVerification: true } },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
