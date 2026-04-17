import bcrypt from "bcrypt";

const run = async () => {
  const hash = await bcrypt.hash("12345678", 10);
  console.log(hash);
};

run();
