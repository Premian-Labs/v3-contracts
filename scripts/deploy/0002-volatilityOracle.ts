import {
  ProxyUpgradeableOwnable__factory,
  VolatilityOracle__factory,
} from '../../typechain';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  const volatilityOracleImplementation = await new VolatilityOracle__factory(
    deployer,
  ).deploy();

  console.log(
    'VolatilityOracle implementation : ',
    volatilityOracleImplementation.address,
  );

  await volatilityOracleImplementation.deployed();

  const volatilityOracleProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(volatilityOracleImplementation.address);

  console.log('VolatilityOracle proxy : ', volatilityOracleProxy.address);

  await volatilityOracleProxy.deployed();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
