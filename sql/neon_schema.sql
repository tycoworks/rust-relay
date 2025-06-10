--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: instruments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instruments (
    id integer NOT NULL,
    symbol text NOT NULL,
    name text
);

ALTER TABLE ONLY public.instruments REPLICA IDENTITY FULL;


--
-- Name: instruments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.instruments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: instruments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.instruments_id_seq OWNED BY public.instruments.id;


--
-- Name: trades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trades (
    id integer NOT NULL,
    instrument_id integer,
    quantity integer NOT NULL,
    price numeric NOT NULL,
    executed_at timestamp without time zone NOT NULL
);

ALTER TABLE ONLY public.trades REPLICA IDENTITY FULL;


--
-- Name: trades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trades_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trades_id_seq OWNED BY public.trades.id;


--
-- Name: instruments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instruments ALTER COLUMN id SET DEFAULT nextval('public.instruments_id_seq'::regclass);


--
-- Name: trades id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trades ALTER COLUMN id SET DEFAULT nextval('public.trades_id_seq'::regclass);


--
-- Name: instruments instruments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instruments
    ADD CONSTRAINT instruments_pkey PRIMARY KEY (id);


--
-- Name: trades trades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trades
    ADD CONSTRAINT trades_pkey PRIMARY KEY (id);


--
-- Name: trades trades_instrument_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trades
    ADD CONSTRAINT trades_instrument_id_fkey FOREIGN KEY (instrument_id) REFERENCES public.instruments(id);


--
-- Name: mz_pub; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION mz_pub WITH (publish = 'insert, update, delete, truncate');


--
-- Name: mz_publication; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION mz_publication WITH (publish = 'insert, update, delete, truncate');


--
-- Name: mz_pub instruments; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION mz_pub ADD TABLE ONLY public.instruments;


--
-- Name: mz_publication instruments; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION mz_publication ADD TABLE ONLY public.instruments;


--
-- Name: mz_pub trades; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION mz_pub ADD TABLE ONLY public.trades;


--
-- Name: mz_publication trades; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION mz_publication ADD TABLE ONLY public.trades;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO mz_user;


--
-- Name: TABLE instruments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.instruments TO mz_user;


--
-- Name: TABLE trades; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.trades TO mz_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO neon_superuser WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON TABLES TO neon_superuser WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE neondb_owner IN SCHEMA public GRANT SELECT ON TABLES TO mz_user;


--
-- PostgreSQL database dump complete
--

