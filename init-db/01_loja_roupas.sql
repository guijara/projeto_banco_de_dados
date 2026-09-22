
BEGIN;

-- =========================================
-- LIMPEZA (permite reexecutar o script)
-- =========================================
DROP TABLE IF EXISTS item_ordem_compra CASCADE;
DROP TABLE IF EXISTS ordem_compra CASCADE;
DROP TABLE IF EXISTS item_venda CASCADE;
DROP TABLE IF EXISTS venda CASCADE;
DROP TABLE IF EXISTS short CASCADE;
DROP TABLE IF EXISTS calca CASCADE;
DROP TABLE IF EXISTS parte_de_baixo CASCADE;
DROP TABLE IF EXISTS meia CASCADE;
DROP TABLE IF EXISTS camiseta CASCADE;
DROP TABLE IF EXISTS roupa CASCADE;
DROP TABLE IF EXISTS endereco CASCADE;
DROP TABLE IF EXISTS fornecedor CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;

DROP FUNCTION IF EXISTS criar_ordem_compra(INT, JSONB);

DROP TYPE IF EXISTS comprimento_short_enum;
DROP TYPE IF EXISTS tipo_barra_enum;
DROP TYPE IF EXISTS modelagem_calca_enum;
DROP TYPE IF EXISTS altura_cintura_enum;
DROP TYPE IF EXISTS comprimento_meia_enum;
DROP TYPE IF EXISTS manga_enum;
DROP TYPE IF EXISTS status_ordem_compra_enum;
DROP TYPE IF EXISTS forma_pagamento_enum;
DROP TYPE IF EXISTS tamanho_enum;
DROP TYPE IF EXISTS tipo_roupa_enum;

-- =========================================
-- ENUMS
-- =========================================
CREATE TYPE tipo_roupa_enum AS ENUM ('camiseta', 'meia', 'calca', 'short');
CREATE TYPE tamanho_enum AS ENUM ('U', 'PP', 'P', 'M', 'G', 'GG', 'XG');
CREATE TYPE forma_pagamento_enum AS ENUM ('pix', 'cartao_credito', 'cartao_debito', 'boleto');
CREATE TYPE status_ordem_compra_enum AS ENUM ('pendente', 'parcial', 'recebida', 'cancelada');
CREATE TYPE manga_enum AS ENUM ('curta', 'longa', 'regata');
CREATE TYPE comprimento_meia_enum AS ENUM ('soquete', 'cano_medio', 'cano_alto');
CREATE TYPE altura_cintura_enum AS ENUM ('alta', 'media', 'baixa');
CREATE TYPE modelagem_calca_enum AS ENUM ('skinny', 'reta', 'flare', 'wide_leg', 'jogger', 'cargo');
CREATE TYPE tipo_barra_enum AS ENUM ('italiana', 'dobrada', 'desfiada', 'com_punho');
CREATE TYPE comprimento_short_enum AS ENUM ('curto', 'medio', 'bermuda');

-- =========================================
-- PESSOAS
-- =========================================
CREATE TABLE cliente (
    id_cliente      SERIAL PRIMARY KEY,
    cpf             VARCHAR(11) NOT NULL UNIQUE,
    nome_completo   VARCHAR NOT NULL,
    data_nascimento DATE,
    celular         VARCHAR,
    email           VARCHAR
);

CREATE TABLE fornecedor (
    id_fornecedor SERIAL PRIMARY KEY,
    nome          VARCHAR NOT NULL,
    email         VARCHAR,
    telefone      VARCHAR,
    cnpj          VARCHAR(14) NOT NULL UNIQUE
);

CREATE TABLE endereco (
    id_endereco   SERIAL PRIMARY KEY,
    id_cliente    INT REFERENCES cliente (id_cliente),
    id_fornecedor INT REFERENCES fornecedor (id_fornecedor),
    rua           VARCHAR NOT NULL,
    bairro        VARCHAR NOT NULL,
    cidade        VARCHAR NOT NULL,
    num_casa      VARCHAR NOT NULL,
    cep           VARCHAR(8) NOT NULL,
    CONSTRAINT chk_endereco_dono
        CHECK (id_cliente IS NOT NULL OR id_fornecedor IS NOT NULL)
);

-- =========================================
-- ROUPA E ESPECIALIZAÇÕES
-- =========================================
CREATE TABLE roupa (
    id_roupa   SERIAL PRIMARY KEY,
    nome       VARCHAR NOT NULL,
    preco      NUMERIC(10,2) NOT NULL,
    tamanho    tamanho_enum NOT NULL,
    cor        VARCHAR,
    malha      VARCHAR,
    tipo_roupa tipo_roupa_enum NOT NULL,
    quantidade INT NOT NULL DEFAULT 0
);

CREATE TABLE camiseta (
    id_roupa INT PRIMARY KEY REFERENCES roupa (id_roupa) ON DELETE CASCADE,
    manga    manga_enum NOT NULL
);

CREATE TABLE meia (
    id_roupa    INT PRIMARY KEY REFERENCES roupa (id_roupa) ON DELETE CASCADE,
    comprimento comprimento_meia_enum NOT NULL
);

CREATE TABLE parte_de_baixo (
    id_roupa          INT PRIMARY KEY REFERENCES roupa (id_roupa) ON DELETE CASCADE,
    altura_cintura    altura_cintura_enum NOT NULL,
    medida_cintura_cm NUMERIC(5,1),
    medida_quadril_cm NUMERIC(5,1)
);

CREATE TABLE calca (
    id_roupa   INT PRIMARY KEY REFERENCES parte_de_baixo (id_roupa) ON DELETE CASCADE,
    modelagem  modelagem_calca_enum NOT NULL,
    tipo_barra tipo_barra_enum
);

CREATE TABLE short (
    id_roupa     INT PRIMARY KEY REFERENCES parte_de_baixo (id_roupa) ON DELETE CASCADE,
    comprimento  comprimento_short_enum NOT NULL,
    possui_forro BOOLEAN NOT NULL DEFAULT FALSE
);

-- =========================================
-- VENDAS
-- =========================================
CREATE TABLE venda (
    id_venda        SERIAL PRIMARY KEY,
    id_cliente      INT NOT NULL REFERENCES cliente (id_cliente),
    data_hora_venda TIMESTAMP NOT NULL DEFAULT now(),
    forma_pagamento forma_pagamento_enum NOT NULL
);

CREATE TABLE item_venda (
    id_item_venda  SERIAL PRIMARY KEY,
    id_venda       INT NOT NULL REFERENCES venda (id_venda) ON DELETE CASCADE,
    id_roupa       INT NOT NULL REFERENCES roupa (id_roupa),
    quantidade     INT NOT NULL,
    preco_unitario NUMERIC(10,2) NOT NULL
);

-- =========================================
-- COMPRAS
-- =========================================
CREATE TABLE ordem_compra (
    id_ordem_compra  SERIAL PRIMARY KEY,
    id_fornecedor    INT NOT NULL REFERENCES fornecedor (id_fornecedor),
    valor_total      NUMERIC(10,2) NOT NULL,
    data_pedido      DATE NOT NULL DEFAULT current_date,
    data_recebimento DATE,
    status           status_ordem_compra_enum NOT NULL DEFAULT 'pendente'
);

COMMENT ON COLUMN ordem_compra.valor_total IS
    'Calculado uma única vez na criação da ordem, a partir dos itens';

CREATE TABLE item_ordem_compra (
    id_item_ordem_compra SERIAL PRIMARY KEY,
    id_ordem_compra      INT NOT NULL REFERENCES ordem_compra (id_ordem_compra) ON DELETE CASCADE,
    id_roupa             INT NOT NULL REFERENCES roupa (id_roupa),
    quantidade_pedida    INT NOT NULL,
    quantidade_recebida  INT NOT NULL DEFAULT 0,
    preco_unitario       NUMERIC(10,2) NOT NULL
);

-- =========================================
-- FUNÇÃO: cria a ordem de compra já com o valor_total calculado
-- =========================================
CREATE OR REPLACE FUNCTION criar_ordem_compra(p_id_fornecedor INT, p_itens JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_ordem INT;
    v_total    NUMERIC(10,2);
BEGIN
    IF p_itens IS NULL OR jsonb_array_length(p_itens) = 0 THEN
        RAISE EXCEPTION 'A ordem de compra precisa ter pelo menos um item';
    END IF;

    SELECT SUM((i ->> 'quantidade_pedida')::INT * (i ->> 'preco_unitario')::NUMERIC(10,2))
      INTO v_total
      FROM jsonb_array_elements(p_itens) AS i;

    INSERT INTO ordem_compra (id_fornecedor, valor_total)
    VALUES (p_id_fornecedor, v_total)
    RETURNING id_ordem_compra INTO v_id_ordem;

    INSERT INTO item_ordem_compra (id_ordem_compra, id_roupa, quantidade_pedida, preco_unitario)
    SELECT v_id_ordem,
           (i ->> 'id_roupa')::INT,
           (i ->> 'quantidade_pedida')::INT,
           (i ->> 'preco_unitario')::NUMERIC(10,2)
      FROM jsonb_array_elements(p_itens) AS i;

    RETURN v_id_ordem;
END;
$$;

COMMIT;