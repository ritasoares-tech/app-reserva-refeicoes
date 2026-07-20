import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "App Cantina — Reservas de Refeições" },
      {
        name: "description",
        content:
          "Plataforma de reservas de refeições da cantina escolar: gestão de menus, saldos e responsabilidade dos alunos.",
      },
      { property: "og:title", content: "App Cantina — Reservas de Refeições" },
      {
        property: "og:description",
        content:
          "Plataforma de reservas de refeições da cantina escolar: gestão de menus, saldos e responsabilidade dos alunos.",
      },
    ],
  }),
  component: Index,
});

// A app original (HTML/CSS/JS) vive em /public/legacy e é servida tal como está.
// Aqui apenas a mostramos em ecrã inteiro, sem alterar o código original.
function Index() {
  return (
    <iframe
      src="/legacy/index.html"
      title="App Cantina"
      style={{
        position: "fixed",
        inset: 0,
        width: "100%",
        height: "100%",
        border: "none",
      }}
    />
  );
}
