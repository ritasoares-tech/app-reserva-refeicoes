# Plano: Tornar a base de dados segura (aluno vs cantina)

O objetivo é deixar de confiar no browser para decidir quem é aluno e quem é cantina, e passar essa decisão para a base de dados, onde não pode ser falsificada.

## Como está hoje (o problema)

```text
Browser  →  anon key (igual para todos)  →  Supabase
   |
   └─ role = "aluno" ou "cantina"  (decidido SÓ no browser, falsificável)
```

- As passwords estão guardadas nas tabelas `alunos` / `cantina`.
- O login compara emails "à mão"; o poder real vem todo da anon key.
- Resultado: qualquer pessoa pode, pela consola, agir como cantina.

## Como vai ficar (o objetivo)

```text
Browser → login Supabase Auth → token pessoal → Supabase
   |
   └─ a BD sabe QUEM és (auth.uid) e QUAL o teu role (tabela user_roles)
       → RLS decide, linha a linha, o que podes ver/alterar
```

---

## Passos

### 1. Migrar os logins para Supabase Auth real
- Cada aluno e cada funcionário da cantina passa a ser um utilizador real do Supabase Auth.
- Como são poucas contas de cantina (2–5), crio-as manualmente; os alunos são migrados a partir da tabela `alunos` atual.
- As tabelas `alunos`/`cantina` deixam de guardar passwords — passam a ligar-se ao utilizador Auth por `user_id`.

### 2. Tabela de roles separada
- Nova tabela `user_roles (user_id, role)` com `role` = `aluno` ou `cantina`.
- Função de segurança `has_role(user_id, role)` (security definer) para as políticas usarem sem risco de recursão.
- Regra de ouro: o role **nunca** fica na tabela do aluno (evita escalonamento de privilégios).

### 3. Ativar RLS em cada tabela
Políticas por role, por exemplo:

| Tabela      | Aluno                                   | Cantina                     |
|-------------|-----------------------------------------|-----------------------------|
| `reservas`  | vê/altera só as suas (`aluno_id = eu`)  | vê/altera todas             |
| `menus`     | só lê                                   | cria / edita / apaga        |
| `alunos`    | vê só o seu registo                     | vê todos                    |
| `cantina`   | sem acesso                              | vê o seu                    |
| `user_roles`| lê o seu                                | (gerido pela cantina/sistema)|

### 4. Ajustar o código da app
- `supabase.js`: mantém a anon key (é normal e público), mas agora o token pessoal do login é que dá poderes.
- `app.js` (login): passa a descobrir o role a partir de `user_roles`, não de comparar tabelas.
- Restante código (`aluno.js`, `cantina.js`) continua a funcionar — as queries deixam de precisar de filtrar "à mão" porque a RLS já garante.

### 5. (Depois) Regras de negócio na BD
Só após a segurança estar de pé: os triggers de horários, limite de 2 cancelamentos e liquidação de dívida, para ficarem à prova de contorno.

---

## Detalhes técnicos

- Projeto usa Supabase **próprio** (anon key direta em `supabase.js`), não Lovable Cloud. Por isso o SQL (tabelas, `has_role`, políticas RLS) é entregue como blocos para aplicares no **SQL Editor** do teu Supabase, pela ordem indicada — e eu corrijo se der erro. As alterações de código (`app.js` etc.) faço eu diretamente aqui.
- Migração de alunos existentes para `auth.users`: feita por um script/SQL único; cada aluno recebe uma password inicial (ou fluxo de "definir password").
- `has_role` como `security definer` + `search_path=public` para evitar recursão de RLS.
- Ordem de aplicação: (1) criar `user_roles` + `has_role` → (2) ligar `alunos`/`cantina` a `user_id` → (3) ativar RLS + políticas → (4) ajustar código → testar login aluno e cantina.

---

## Ponto que preciso de confirmar contigo antes de avançar

A migração dos **alunos atuais** para logins reais: preferes que cada aluno **mantenha o email** e receba uma **password inicial** definida por nós, ou que passem por um fluxo de "recuperar/definir password" no primeiro acesso? Isto afeta como faço a migração.