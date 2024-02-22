import { prisma } from "@/lib/db";

export default async function Home() {
  const user = await prisma.user.findFirst({
    where: {
      email: "tkddls8848@naver.com",
    },
  });
  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <div>Hello {user?.name}</div>
    </main>
  );
}
