import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

let main = async () => {
  const user = await prisma.user.upsert({
    where: { email: "test@test.com" },
    update: {},
    create: {
      email: "test@test.com",
      name: "PSI",
      password: "password",
    },
  });
  console.log(user);
};

main()
  .then(() => prisma.$disconnect)
  .catch(async (e) => {
    console.log(e);
    await prisma.$disconnect;
    process.exit(1);
  });
