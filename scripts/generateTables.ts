import { generateTables } from '../utils/tables/model';
import { ChainID } from '../utils/deployment/types';

async function main() {
  const chain = ChainID.Arbitrum;
  await generateTables(chain);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
