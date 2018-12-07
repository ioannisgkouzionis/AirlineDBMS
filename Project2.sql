--
-- PostgreSQL database dump
--

-- Dumped from database version 9.4.1
-- Dumped by pg_dump version 9.4.1
-- Started on 2015-06-05 10:58:36

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 200 (class 3079 OID 11855)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 2283 (class 0 OID 0)
-- Dependencies: 200
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- TOC entry 599 (class 1247 OID 159627)
-- Name: action; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE action AS ENUM (
    'buy',
    'reserve',
    'cancel'
);


ALTER TYPE action OWNER TO postgres;

--
-- TOC entry 602 (class 1247 OID 159634)
-- Name: days; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE days AS ENUM (
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN'
);


ALTER TYPE days OWNER TO postgres;

--
-- TOC entry 605 (class 1247 OID 159650)
-- Name: sex; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE sex AS ENUM (
    'M',
    'F'
);


ALTER TYPE sex OWNER TO postgres;

--
-- TOC entry 608 (class 1247 OID 159656)
-- Name: type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE type AS ENUM (
    'gstaff',
    'tagent'
);


ALTER TYPE type OWNER TO postgres;

--
-- TOC entry 214 (class 1255 OID 159661)
-- Name: calc_free_seats(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION calc_free_seats(v_fsc_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
v_free_seats integer;
BEGIN
	SELECT x.num_seats-(SELECT COUNT(*) r_seats FROM transactions t WHERE fschedule_id=v_fsc_id AND action<>'cancel' AND NOT EXISTS(SELECT tid FROM waitinglist WHERE tid=t.t_id)) free_seats FROM
	(SELECT num_seats FROM aircraft_type at INNER JOIN aircraft a ON at.id = a.type_id
	INNER JOIN flightschedule fs ON a.code=fs.aircraft_code WHERE fs.fschedule_id = v_fsc_id) x INTO v_free_seats;
	RETURN v_free_seats;
END;
$$;


ALTER FUNCTION public.calc_free_seats(v_fsc_id integer) OWNER TO postgres;

--
-- TOC entry 215 (class 1255 OID 159662)
-- Name: calcs_1(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION calcs_1(v_tagent_id integer, OUT v_ag_id integer, OUT v_agent_name character varying, OUT v_sales_amount numeric) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY
	SELECT am.agent_id, name, TotAmount FROM
	(SELECT sum(amount) TotAmount, mt.id agent_id FROM get_trans_details t INNER JOIN madetransaction mt ON t.t_id=mt.t_id INNER JOIN cashier c ON t.t_id=c.tid 	   WHERE t_date::date BETWEEN (date_trunc('week', (current_date)::timestamp)::date) 
	AND ((date_trunc('week', (current_date)::timestamp)+ '6 days'::interval)::date) AND mt.id=v_tagent_id AND action='buy' GROUP BY mt.id) am 
	INNER JOIN travelagency ta ON am.agent_id=ta.id;
END;
$$;


ALTER FUNCTION public.calcs_1(v_tagent_id integer, OUT v_ag_id integer, OUT v_agent_name character varying, OUT v_sales_amount numeric) OWNER TO postgres;

--
-- TOC entry 216 (class 1255 OID 159663)
-- Name: calcs_2(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION calcs_2() RETURNS TABLE(v_month text, v_total numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
	-- ypologismos twn esodwn gia kathe mina tou trexontos etous
	RETURN QUERY 
	WITH w AS ( SELECT month, sum(amount) AS total FROM (SELECT date_trunc('month',t_date) AS month, amount FROM get_trans_details gtd 
	INNER JOIN madetransaction mt ON gtd.t_id=mt.t_id 
	INNER JOIN cashier c ON gtd.t_id=c.tid) z GROUP BY month )
	SELECT to_char(month, 'Mon-YYYY') AS month, COALESCE(total, 0) AS total 
	FROM (SELECT (SELECT date_trunc('year', CURRENT_DATE::timestamp)) + (interval '1' month * GENERATE_SERIES(0,11)) as month) m LEFT OUTER JOIN w USING(month);
END;
$$;


ALTER FUNCTION public.calcs_2() OWNER TO postgres;

--
-- TOC entry 217 (class 1255 OID 159664)
-- Name: calcs_3(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION calcs_3(OUT v_cnt_tr bigint, OUT v_fsc_id integer, OUT v_fday_week date, OUT v_lday_week date) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY
	SELECT max(fl_count) cnt,fschedule_id,week::date, ((date_trunc('week', (week)::timestamp)+ '6 days'::interval)::date) 
	FROM 
	(
		SELECT fschedule_id, week, count(*) fl_count 
		FROM 
		(
			SELECT date_trunc('week',fdate)::timestamp as week, amount, fschedule_id,extract(week from fdate) week_num
			FROM get_trans_details gtd 
			INNER JOIN madetransaction mt ON gtd.t_id=mt.t_id 
			INNER JOIN cashier c ON gtd.t_id=c.tid
		) z GROUP BY fschedule_id, week
	) v
	GROUP BY week,fschedule_id
	ORDER BY cnt desc LIMIT 1;
END;
$$;


ALTER FUNCTION public.calcs_3(OUT v_cnt_tr bigint, OUT v_fsc_id integer, OUT v_fday_week date, OUT v_lday_week date) OWNER TO postgres;

--
-- TOC entry 218 (class 1255 OID 159665)
-- Name: calcs_4(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION calcs_4(OUT v_fsc_id integer, OUT v_fday_week date, OUT v_lday_week date, OUT v_tot_amount numeric, OUT v_tot_expenses numeric, OUT v_net_amount numeric) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
DECLARE
v_trans RECORD;
BEGIN
        DROP TABLE IF EXISTS temp1;
        CREATE TEMP TABLE temp1 AS
        SELECT fschedule_id, week::date , ((date_trunc('week', (week)::timestamp)+ '6 days'::interval)::date) lday_week, sum(amount) AS fl_sales, 0.0 expenses 
        FROM 
        (
                SELECT date_trunc('week',fdate)::timestamp AS week, amount, fschedule_id 
                FROM get_trans_details gtd 
                INNER JOIN madetransaction mt ON gtd.t_id=mt.t_id 
                INNER JOIN cashier c ON gtd.t_id=c.tid
        ) z GROUP BY fschedule_id, week;

        FOR v_trans IN select fschedule_id, week, fl_sales FROM temp1 LOOP

        UPDATE temp1 SET expenses=(
                SELECT (CASE WHEN dom=1 THEN (30*dom_dr)+((15*dom_dr)*2) ELSE (60*dom_dr)+((30*dom_dr)*2) END) expenses FROM
                (
                        SELECT (CASE WHEN dep_country='Greece' AND dest_country='Greece' THEN 1 ELSE 0 END) dom,
                        flight_hours(((arr_time)-(dep_time))::time)/60 dom_dr,dep_country, dest_country
                        FROM get_flight_details gfd 
                        WHERE gfd.fschedule_id=v_trans.fschedule_id
                ) 
        q);

        END LOOP;
        RETURN query SELECT fschedule_id,week,lday_week,fl_sales,round(expenses,2),round((fl_sales-expenses),2) net_amount FROM temp1 ORDER BY net_amount desc LIMIT 1;
END;
$$;


ALTER FUNCTION public.calcs_4(OUT v_fsc_id integer, OUT v_fday_week date, OUT v_lday_week date, OUT v_tot_amount numeric, OUT v_tot_expenses numeric, OUT v_net_amount numeric) OWNER TO postgres;

--
-- TOC entry 219 (class 1255 OID 159666)
-- Name: calcs_5(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION calcs_5(OUT v_flight_code integer, OUT v_dep_city character varying, OUT v_fl_date timestamp without time zone, OUT v_aircraft_code integer, OUT v_type character varying) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY SELECT gfd.fschedule_id,gfd.dep_city,gfd.fdate+gfd.dep_time fl_date,gfd.aircraft_code,air_tp.type 
	FROM get_flight_details gfd INNER JOIN aircraft_type air_tp ON gfd.aircraft_type=air_tp.id 
	WHERE date_part('month',fdate::timestamp)=(date_part('month',CURRENT_DATE)-1) AND gfd.dep_city='Athens' ORDER BY fl_date, fschedule_id; 

END;
$$;


ALTER FUNCTION public.calcs_5(OUT v_flight_code integer, OUT v_dep_city character varying, OUT v_fl_date timestamp without time zone, OUT v_aircraft_code integer, OUT v_type character varying) OWNER TO postgres;

--
-- TOC entry 220 (class 1255 OID 159667)
-- Name: cancel_by_company(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION cancel_by_company() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_wtr_id integer;
	v_type type;
	v_new_trdate timestamp;
	v_trans RECORD;
	v_flights get_flight_details%ROWTYPE;
BEGIN
        SELECT localtimestamp INTO v_new_trdate;
        FOR v_flights IN SELECT gfd.fschedule_id FROM get_flight_details gfd 
        WHERE v_new_trdate BETWEEN ((gfd.fdate+gfd.dep_time)-'12:00:00'::interval) AND ((gfd.fdate+gfd.dep_time)-'04:00:00'::interval) LOOP
                FOR v_trans IN SELECT gtd.t_id, gtd.price, gtd.fschedule_id, (gtd.fdate+gtd.dep_time) v_dep_time 
                FROM get_trans_details gtd WHERE (gtd.fschedule_id=v_flights.fschedule_id) AND gtd.action='reserve' LOOP                          
			-- allazoume to action tis sinallagis se cancel
			UPDATE transactions SET action='cancel', t_date=v_new_trdate WHERE t_id=v_trans.t_id AND action='reserve';
			DELETE FROM reservation WHERE tid=v_trans.t_id;
			IF calc_free_seats(v_trans.fschedule_id)>0 THEN
				-- pairnoume to id tis sinallagis pou eina ston pinaka waitinglist kai i opoia tha proxwrisei se agora tou eisitiriou
				SELECT t_id FROM transactions t INNER JOIN waitinglist w on t.t_id=w.tid 
				WHERE t.fschedule_id=v_trans.fschedule_id ORDER BY t_id,t_date LIMIT 1 INTO v_wtr_id;
				IF NOT FOUND THEN
					EXIT;
				END IF;
				-- pairnoume poios ekane tin sinallagi pou vrisketai ston pinaka waitinglist 
				SELECT type FROM madetransaction WHERE t_id=v_wtr_id INTO v_type;
				-- elegxw an perasan 4 wres prin ginei i ptisi, kathws toulaxiston 4 wres prin tin ptisi mporei na ginei agora 
				-- eisitiriou apo kapoion pou itan sto waitinglist
				IF (localtimestamp)<=(v_trans.v_dep_time-'04:00'::interval) THEN
					-- allazoume to action tis sinallagis pou pairnoume apo to waitinglist se buy
					UPDATE transactions SET action='buy', t_date=v_new_trdate WHERE t_id=v_wtr_id;
					-- elegxoume an autos pou ekleise tin sinallagi einai taksidiwtikos praktoras
					IF v_type='tagent' THEN
						INSERT INTO cashier(tid,amount) VALUES (v_wtr_id,v_trans.price*0.988);
					ELSE
						INSERT INTO cashier(tid,amount) VALUES (v_wtr_id,v_trans.price);
					END IF;
					-- afou oloklirwthei i agora tou eisitiriou, diagrafoume tin sinallagi apo ton pinaka waitinglist
					DELETE FROM waitinglist WHERE tid=v_wtr_id;
				END IF;
			END IF;
                END LOOP;
        END LOOP;
END;
$$;


ALTER FUNCTION public.cancel_by_company() OWNER TO postgres;

--
-- TOC entry 221 (class 1255 OID 159668)
-- Name: cancel_by_customer(integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION cancel_by_customer(v_c_id integer, v_fschedule_id integer, v_fl_date date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_tr_id integer;
	v_wtr_id integer;
	v_type type;
	v_dep_time timestamp;
	v_dep_time_wtr timestamp;
	v_price numeric;
	v_rcnt integer;
BEGIN
	SELECT t_id, (fdate+dep_time) v_dep_time FROM get_trans_details WHERE c_id=v_c_id AND action='reserve' AND fschedule_id=v_fschedule_id 
	AND fdate=v_fl_date INTO v_tr_id, v_dep_time;
        SELECT 1 FROM reservation WHERE tid=v_tr_id INTO v_rcnt;
        IF v_rcnt=1 THEN
		-- elegxw an perasan 12 wres prin ginei i ptisi 
		IF (localtimestamp)<=(v_dep_time-'12:00'::interval) THEN
			UPDATE transactions SET action='cancel' WHERE t_id=v_tr_id;	
			DELETE FROM reservation WHERE tid=v_tr_id;	        
			-- pairnoume to id tis sinallagis pou eina ston pinaka waitinglist kai i opoia tha proxwrisei se agora tou eisitiriou
			SELECT t_id, (fdate+dep_time), price FROM get_trans_details gtd INNER JOIN waitinglist w on gtd.t_id=w.tid 
			WHERE gtd.fschedule_id=v_fschedule_id ORDER BY t_id,t_date LIMIT 1 INTO v_wtr_id, v_dep_time_wtr, v_price;
			IF NOT FOUND THEN 
				EXIT;
			END IF;
			-- pairnoume poios ekane tin sinallagi pou vrisketai ston pinaka waitinglist 
			SELECT type FROM madetransaction WHERE t_id=v_wtr_id INTO v_type;
			-- elegxw an perasan 4 wres prin ginei i ptisi, 
			-- kathws toulaxiston 4 wres prin tin ptisi mporei na ginei agora eisitiriou apo kapoion pou itan sto waitinglist
			IF (localtimestamp)<=(v_dep_time_wtr-'04:00'::interval) THEN
				-- allazoume to action tis sinallagis pou pairnoume apo to waitinglist se buy
				UPDATE transactions SET action='buy' WHERE t_id=v_wtr_id;
				-- elegxoume an autos pou ekleise tin sinallagi einai taksidiwtikos praktoras
				IF v_type='tagent' THEN
					INSERT INTO cashier(tid,amount) VALUES (v_wtr_id,v_price*0.988);
				ELSE
					INSERT INTO cashier(tid,amount) VALUES (v_wtr_id,v_price);
				END IF;
				-- afou oloklirwthei i agora tou eisitiriou, diagrafoume tin sinallagi apo ton pinaka waitinglist
				DELETE FROM waitinglist WHERE tid=v_wtr_id;
			END IF;
		ELSE
                        RAISE EXCEPTION 'You can cancel your ticket until 12 hours before departure time.';
                END IF;
        ELSE
		UPDATE transactions SET action='cancel' WHERE t_id=v_tr_id;
                DELETE FROM waitinglist WHERE tid=v_tr_id;
        END IF;
	RETURN;
END;
$$;


ALTER FUNCTION public.cancel_by_customer(v_c_id integer, v_fschedule_id integer, v_fl_date date) OWNER TO postgres;

--
-- TOC entry 223 (class 1255 OID 159669)
-- Name: check_flight_fstaff(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION check_flight_fstaff(v_fschedule_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	pils integer;
	atts integer;
	output text;
BEGIN
	 IF (SELECT COUNT(*) FROM flightschedule WHERE fschedule_id=v_fschedule_id)=0 THEN
		RAISE EXCEPTION 'Flight % not found.', v_fschedule_id;
	END IF;
	SELECT count(*) from staffschedule ss inner join fspilots pil ON ss.emp_id=pil.emp_id WHERE fschedule_id=v_fschedule_id INTO pils;
	SELECT count(*) from staffschedule ss inner join fsattendant att ON ss.emp_id=att.emp_id WHERE fschedule_id=v_fschedule_id INTO atts;
	IF pils<1 OR atts<2 THEN
		output='Flight ' || v_fschedule_id || ' isnt ready to go.'; -- || : concatenate
	ELSE
		output='Flight ' || v_fschedule_id || ' is ready to go.';
	END IF;
	RETURN output;
END;
$$;


ALTER FUNCTION public.check_flight_fstaff(v_fschedule_id integer) OWNER TO postgres;

--
-- TOC entry 224 (class 1255 OID 159670)
-- Name: delete_by_company(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION delete_by_company() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_trans transactions%ROWTYPE;
	v_flights get_flight_details%ROWTYPE;
BEGIN
	FOR v_flights IN SELECT gfd.fschedule_id FROM get_flight_details gfd INNER JOIN flightdone fld ON gfd.fschedule_id=fld.fschedule_id 
        WHERE (localtimestamp-(gfd.fdate+gfd.dep_time))>='12:00'::interval LOOP
                FOR v_trans IN (SELECT t.t_id FROM transactions t inner join reservation r on t.t_id=r.tid WHERE t.fschedule_id=v_flights.fschedule_id
				union
				SELECT t.t_id FROM transactions t inner join waitinglist w on t.t_id=w.tid WHERE t.fschedule_id=v_flights.fschedule_id) LOOP
                        -- diagrafoume tis sinallages apo tous pinakes reservation kai waitinglist
			DELETE FROM reservation WHERE tid=v_trans.t_id;
			DELETE FROM waitinglist WHERE tid=v_trans.t_id;
		END LOOP;
	END LOOP;
END;
$$;


ALTER FUNCTION public.delete_by_company() OWNER TO postgres;

--
-- TOC entry 225 (class 1255 OID 159671)
-- Name: flight_hours(time without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION flight_hours(t time without time zone) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE 
	m double precision;
	s numeric;
BEGIN
	SELECT (EXTRACT(EPOCH FROM t)/60) INTO m;
	SELECT round(m::numeric, 2) INTO s;
	RETURN s;
END;
$$;


ALTER FUNCTION public.flight_hours(t time without time zone) OWNER TO postgres;

--
-- TOC entry 226 (class 1255 OID 159672)
-- Name: insert_agent_transaction(integer, integer, action, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_agent_transaction(v_fschedule_id integer, v_customer_id integer, v_action action, v_agent_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_tran_date timestamp; 
	v_id integer;
	v_t_id integer;
	v_freeseats integer; 
	v_amount numeric;
	v_trans_time timestamp;
	v_dep_time timestamp;
	cur_fl integer;
	v_dep1 integer;
	v_dest1 integer;
	v_dep2 integer;
	v_dest2 integer;
	old_action action;
	v_dep_country character varying;
	v_dest_country character varying;
BEGIN
	SELECT localtimestamp INTO v_tran_date;
        IF (SELECT COUNT(*) FROM travelagency WHERE id=v_agent_id)=0 THEN
		RAISE EXCEPTION 'No tagent with id % found.', v_agent_id;
	END IF;
	SELECT coalesce(MAX(t_id),0) FROM transactions INTO v_id;
	-- an to action einai cancel, tote apotrepw ston xristi na kanei kapoia sinallagi
	IF v_action='cancel' THEN
                RAISE EXCEPTION 'You can only reserve or buy tickets.';
	END IF;
	-- elegxw an o pelatis exei kanei idi sinallagi gia tin ptisi auti
	SELECT count(*) FROM transactions tr WHERE c_id=v_customer_id AND fschedule_id=v_fschedule_id INTO cur_fl;
	IF cur_fl>0 THEN
		RAISE EXCEPTION 'Customer % has already reserved or bought ticket for flight % .',v_customer_id,v_fschedule_id;
	END IF;
	-- elegxw an i ptisi pou paei na kanei sinallagi epikaliptetai me kapoia stin opoia exei idi kanei sinallagi
	SELECT price, fdate+dep_time, departure, destination, dep_country, dest_country FROM get_flight_details 
	WHERE fschedule_id=v_fschedule_id INTO v_amount,v_dep_time, v_dep1, v_dest1,v_dep_country, v_dest_country;
	IF EXISTS (SELECT 1 FROM get_trans_details WHERE c_id=v_customer_id 
	AND v_dep_time BETWEEN (fdate+dep_time)-'00:30'::interval AND (fdate+dep_time)+(arr_time-dep_time)+'00:30'::interval) THEN
		RAISE EXCEPTION 'Customer % has a programmed flight in same hour and date.',v_customer_id;
	END IF; 
	IF (SELECT count(*) FROM get_trans_details t1,get_trans_details t2 
	WHERE t1.departure=t2.departure AND t1.fdate=t2.fdate AND t1.c_id=t2.c_id AND t2.c_id=v_customer_id 
	AND t2.fdate=(select fdate from get_flight_details where fschedule_id=v_fschedule_id) AND t2.action<>'cancel') > 0 THEN
		RAISE EXCEPTION 'You cant fly over than one time from the same airport in the same day.';
	END IF;
	-- den mporei na ginei kratisi eisitiriou an perasoun 12 wres prin tin pragmatopoiisi tis ptisis
	IF v_tran_date>=(v_dep_time-'12:00'::interval) AND v_action='reserve' THEN  
		RAISE EXCEPTION 'You cant reserve ticket for flight % .',v_fschedule_id;
	END IF;
	-- den mporei na ginei agora eisitiriou an perasoun 4 wres prin tin pragmatopoiisi tis ptisis
	IF v_tran_date>=(v_dep_time-'04:00'::interval) AND v_action='buy' THEN  
		RAISE EXCEPTION 'You cant buy ticket for flight % .',v_fschedule_id;
	END IF;
	-- pairnw ta dedomena tis kratisis pou exei kanei autos o pelatis tin idia mera
	SELECT t_date, departure, destination, action FROM get_trans_details 
	WHERE c_id=v_customer_id and t_date::date=v_tran_date::date ORDER BY t_date desc LIMIT 1 INTO v_trans_time, v_dep2, v_dest2, old_action;
	IF (v_dest2=v_dep1) AND (v_dest1=v_dep2) AND v_action='buy' AND old_action='buy' THEN
		IF v_dep_country<>'Greece' OR v_dest_country<>'Greece' THEN
			v_amount=v_amount*0.85;
		ELSE
			v_amount=v_amount*0.92;
		END IF;
	END IF;
	-- get free seats
	SELECT calc_free_seats(v_fschedule_id) INTO v_freeseats;
	-- an to action einai buy kai den yparxoun eleutheres theseis sto aeroplano, tote allazw to action apo buy se reserve
	IF v_action='buy' AND v_freeseats=0 THEN
		v_action='reserve';
	END IF;
	-- insert new transaction in table transactions and table madetransaction
	INSERT INTO transactions(t_id,fschedule_id,c_id,action,t_date) VALUES (v_id+1,v_fschedule_id,v_customer_id,v_action,v_tran_date) RETURNING t_id INTO v_t_id; 
	INSERT INTO madetransaction(id,t_id,type) VALUES (v_agent_id, v_t_id, 'tagent');
	-- an to action einai reserve kai den yparxoun kenes theseis sto aeroplano, tote vazw tin sinallagi auti kai ston pinaka waitinglist
	IF v_action='reserve' AND v_freeseats=0 THEN
		INSERT INTO waitinglist(tid) VALUES (v_t_id);
		RAISE NOTICE 'There arent any free seats for this flight and you have been added to waiting list.';
	END IF;
	-- an to action einai reserve kai yparxoun kenes theseis sto aeroplano, tote vazw tin sinallagi auti kai ston pinaka reservation
	IF v_action='reserve' AND v_freeseats>0 THEN
		INSERT INTO reservation(tid) VALUES (v_t_id);
	END IF;
	-- an to action einai buy kai yparxoun kenes theseis sto aeroplano, tote vazw tin sinallagi auti kai ston pinaka cashier
	-- epeidi i sinallagi kleinetai apo taksidiwtiko grafeio, to amount pou mpainei ston pinaka cashier einai to 98.8% tis aksias tou eisitiriou
	IF v_action='buy' AND v_freeseats>0 THEN
		INSERT INTO cashier(tid,amount) VALUES (v_t_id,v_amount*0.988); 
	END IF;
END;
$$;


ALTER FUNCTION public.insert_agent_transaction(v_fschedule_id integer, v_customer_id integer, v_action action, v_agent_id integer) OWNER TO postgres;

--
-- TOC entry 227 (class 1255 OID 159674)
-- Name: insert_aircraft(integer, numeric, smallint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_aircraft(v_type_id integer, v_total_hours numeric, v_status smallint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	tot_aircrafts integer;
	v_code integer;
BEGIN
	SELECT coalesce(MAX(code),0) FROM aircraft INTO v_code;
        SELECT count(*) FROM aircraft INTO tot_aircrafts;
	IF tot_aircrafts = 7 THEN
		RAISE EXCEPTION 'You cannot insert anymore aircrafts.';
	END IF;
	IF v_total_hours>=150 AND v_status=1 THEN
		RAISE EXCEPTION 'Aircraft has the max flight hours.';
	ELSE 
		INSERT INTO aircraft(code,type_id,total_hours,status) VALUES (v_code+1,v_type_id,v_total_hours,v_status);
	END IF;
END;
$$;


ALTER FUNCTION public.insert_aircraft(v_type_id integer, v_total_hours numeric, v_status smallint) OWNER TO postgres;

--
-- TOC entry 228 (class 1255 OID 159675)
-- Name: insert_aircraft_type(character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_aircraft_type(v_type character varying, v_num_seats integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	tot_aircraftypes integer;
	v_id integer;
BEGIN
	SELECT coalesce(MAX(id),0) FROM aircraft_type INTO v_id;
        SELECT count(*) FROM aircraft_type INTO tot_aircraftypes;
	IF tot_aircraftypes = 3 THEN
		RAISE EXCEPTION 'You cannot insert anymore aircraft types.';
	ELSE
		INSERT INTO aircraft_type(id,type,num_seats) VALUES (v_id+1,v_type,v_num_seats);
	END IF;
END;
$$;


ALTER FUNCTION public.insert_aircraft_type(v_type character varying, v_num_seats integer) OWNER TO postgres;

--
-- TOC entry 229 (class 1255 OID 159676)
-- Name: insert_airport(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_airport(v_name character varying, v_city character varying, v_country character varying, v_shortcut character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	tot_airports integer;
	v_id integer;
BEGIN
	SELECT coalesce(MAX(code),0) FROM airport INTO v_id;
        SELECT count(*) FROM airport INTO tot_airports;
	IF tot_airports = 6 THEN
		RAISE EXCEPTION 'You cannot insert anymore airports.';
	ELSE
		INSERT INTO airport(code,name,city,country,shortcut) VALUES (v_id+1,v_name,v_city,v_country,v_shortcut);
	END IF;
END;
$$;


ALTER FUNCTION public.insert_airport(v_name character varying, v_city character varying, v_country character varying, v_shortcut character varying) OWNER TO postgres;

--
-- TOC entry 230 (class 1255 OID 159677)
-- Name: insert_attendants(character varying, character varying, character varying, date, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_attendants(v_fname character varying, v_lname character varying, v_job character varying, v_birthdate date, v_phone character varying, v_address character varying, v_nativelang character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
	cnt_attendants integer;
BEGIN
        SELECT coalesce(MAX(id),0) FROM fstaff INTO v_id;
        SELECT COUNT(*) FROM fstaff WHERE job='Attendant' INTO cnt_attendants;
        IF cnt_attendants = 20 THEN
		RAISE EXCEPTION 'You cannot insert anymore attendants.';
        ELSE 
		INSERT INTO fstaff(id, fname, lname, job, birthdate, phone, address) VALUES(v_id+1, v_fname, v_lname, v_job, v_birthdate, v_phone, v_address);
		INSERT INTO fsattendant(emp_id, native_lang) VALUES(v_id+1, v_nativelang);
        END IF;
END;
$$;


ALTER FUNCTION public.insert_attendants(v_fname character varying, v_lname character varying, v_job character varying, v_birthdate date, v_phone character varying, v_address character varying, v_nativelang character varying) OWNER TO postgres;

--
-- TOC entry 231 (class 1255 OID 159678)
-- Name: insert_authoritytests(character varying, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_authoritytests(v_authorityname character varying, v_pass_rank integer, v_description text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
BEGIN
	SELECT coalesce(MAX(testcode),0) FROM authoritytests INTO v_id;
	INSERT INTO authoritytests(testcode,authorityname,pass_rank,description) VALUES (v_id+1,v_authorityname,v_pass_rank,v_description);
END;
$$;


ALTER FUNCTION public.insert_authoritytests(v_authorityname character varying, v_pass_rank integer, v_description text) OWNER TO postgres;

--
-- TOC entry 232 (class 1255 OID 159679)
-- Name: insert_customer(character varying, character varying, integer, sex, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_customer(v_fname character varying, v_lname character varying, v_age integer, v_sex sex, v_phone character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
BEGIN
	SELECT coalesce(MAX(id),0) FROM customer INTO v_id;
	INSERT INTO customer(id,fname,lname,age,sex,phone) VALUES (v_id+1,v_fname,v_lname,v_age,v_sex,v_phone);
END;
$$;


ALTER FUNCTION public.insert_customer(v_fname character varying, v_lname character varying, v_age integer, v_sex sex, v_phone character varying) OWNER TO postgres;

--
-- TOC entry 233 (class 1255 OID 159680)
-- Name: insert_expertise(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_expertise(v_emp_id integer, v_air_type integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
        IF v_air_type NOT IN (SELECT id FROM aircraft_type) THEN
		RAISE EXCEPTION 'The % aircraft type doesnt exist.',v_air_type;
	END IF;
	IF v_emp_id NOT IN (SELECT emp_id FROM fspilots) THEN
		RAISE EXCEPTION 'The % pilot doesnt exist.',v_emp_id;
	END IF;
	INSERT INTO expertise(emp_id,aircraft_type) VALUES (v_emp_id,v_air_type);
END;
$$;


ALTER FUNCTION public.insert_expertise(v_emp_id integer, v_air_type integer) OWNER TO postgres;

--
-- TOC entry 234 (class 1255 OID 159681)
-- Name: insert_flight(integer, integer, time without time zone, time without time zone, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_flight(v_departure integer, v_destination integer, v_dep_time time without time zone, v_arr_time time without time zone, v_price numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
	dr interval;
BEGIN
	SELECT v_arr_time - v_dep_time INTO dr;
	SELECT coalesce(MAX(fcode),0) FROM flight INTO v_id;
	INSERT INTO flight(fcode,departure,destination,dep_time,arr_time,price) VALUES (v_id+1,v_departure,v_destination,v_dep_time,v_arr_time,v_price);
	-- INSERT INTO flight(fcode,departure,destination,dep_time,arr_time,price) VALUES (v_id+2,v_destination,v_departure,v_arr_time+'00:30:00',v_arr_time+dr+'00:30:00',v_price);
END;
$$;


ALTER FUNCTION public.insert_flight(v_departure integer, v_destination integer, v_dep_time time without time zone, v_arr_time time without time zone, v_price numeric) OWNER TO postgres;

--
-- TOC entry 235 (class 1255 OID 159682)
-- Name: insert_flight_days(integer, days); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_flight_days(v_fcode integer, v_days days) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	INSERT INTO flight_days(fcode,days) VALUES (v_fcode,v_days);
END;
$$;


ALTER FUNCTION public.insert_flight_days(v_fcode integer, v_days days) OWNER TO postgres;

--
-- TOC entry 236 (class 1255 OID 159683)
-- Name: insert_flightsprogram(integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_flightsprogram(v_aircraft_type integer, v_flight_code integer, v_start_date date, v_end_date date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_program_id integer;
	cntr character varying;
	air_type character varying;
	v_start_date_2 date;
	v_end_date_2 date;
	v_dep_city character varying;
	day_1 character varying[];
	day_2 character varying;
BEGIN
           IF (SELECT COUNT(*) FROM flight WHERE fcode=v_flight_code) = 0 THEN
		RAISE EXCEPTION 'Flight % does not exists.', v_flight_code;
           END IF;
           IF (SELECT COUNT(*) FROM aircraft_type WHERE id=v_aircraft_type) = 0 THEN
		RAISE EXCEPTION 'Aircraft type % does not exists.', v_aircraft_type;
           END IF;
           SELECT city FROM airport a INNER JOIN flight f on a.code=f.departure WHERE f.fcode=v_flight_code INTO v_dep_city;
           IF v_dep_city<>'Athens' THEN
		RAISE EXCEPTION 'You must insert a basic flight.';
           END IF;
           SELECT coalesce(MAX(program_id),0) FROM flightsprogram INTO v_program_id;
	   SELECT ar.country FROM airport ar,    
           (SELECT * FROM airport a INNER JOIN flight f ON a.code=f.departure AND city='Athens') x
           WHERE ar.code=x.destination AND x.fcode=v_flight_code INTO cntr; 
	   SELECT type FROM aircraft_type airtype WHERE airtype.id=v_aircraft_type INTO air_type; 
	   IF air_type='Boeing737' THEN 
		IF cntr='Greece' THEN
		   INSERT INTO flightsprogram(aircraft_type,flight_code,start_date,end_date,program_id) VALUES (v_aircraft_type,v_flight_code,v_start_date,v_end_date,v_program_id+1);
		   -- INSERT INTO flightsprogram(aircraft_type,flight_code,start_date,end_date,program_id) VALUES (v_aircraft_type,v_flight_code+1,v_start_date,v_end_date,v_program_id+2);
		ELSE
		   RAISE EXCEPTION 'Aircraft type % cannot join international flights.',v_aircraft_type;
		END IF;
	   ELSE
		INSERT INTO flightsprogram(aircraft_type,flight_code,start_date,end_date,program_id) VALUES (v_aircraft_type,v_flight_code,v_start_date,v_end_date,v_program_id+1);
		-- INSERT INTO flightsprogram(aircraft_type,flight_code,start_date,end_date,program_id) VALUES (v_aircraft_type,v_flight_code+1,v_start_date,v_end_date,v_program_id+2);
	   END IF;
END;
$$;


ALTER FUNCTION public.insert_flightsprogram(v_aircraft_type integer, v_flight_code integer, v_start_date date, v_end_date date) OWNER TO postgres;

--
-- TOC entry 237 (class 1255 OID 159684)
-- Name: insert_flightsprogram1(integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_flightsprogram1(v_aircraft_type integer, v_flight_code integer, v_start_date date, v_end_date date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_program_id integer;
	cntr character varying;
	air_type character varying;
	v_start_date_2 date;
	v_end_date_2 date;
	v_dep_city character varying;
	day_1 character varying[];
	day_2 character varying;
        r_err_code integer = 0;
BEGIN
	BEGIN
                IF (SELECT COUNT(*) FROM flight WHERE fcode=v_flight_code) = 0 THEN
                        ROLLBACK;
                END IF;
                                        
                IF (SELECT COUNT(*) FROM aircraft_type WHERE id=v_aircraft_type) = 0 THEN
                        ROLLBACK;
                END IF;
                        
                SELECT city FROM airport a INNER JOIN flight f on a.code=f.departure WHERE f.fcode=v_flight_code INTO v_dep_city;
                IF v_dep_city<>'Athens' THEN
                        ROLLBACK;
                END IF;

                SELECT coalesce(MAX(program_id),0) FROM flightsprogram INTO v_program_id;
                SELECT ar.country FROM airport ar,    
                (SELECT * FROM airport a INNER JOIN flight f ON a.code=f.departure AND city='Athens') x
                WHERE ar.code=x.destination AND x.fcode=v_flight_code INTO cntr; 
                SELECT type FROM aircraft_type airtype WHERE airtype.id=v_aircraft_type INTO air_type; 
                IF air_type='Boeing737' THEN 
                        IF cntr='Greece' THEN
                                INSERT INTO flightsprogram(aircraft_type,flight_code,start_date,end_date,program_id) VALUES (v_aircraft_type,v_flight_code,v_start_date,v_end_date,v_program_id+1);
                        ELSE
                                ROLLBACK;
                        END IF;
                ELSE
                        INSERT INTO flightsprogram(aircraft_type,flight_code,start_date,end_date,program_id) VALUES (v_aircraft_type,v_flight_code,v_start_date,v_end_date,v_program_id+1);
                END IF;

                EXCEPTION WHEN others THEN
                        r_err_code = 31;
        END;  
        RETURN r_err_code;
END;
$$;


ALTER FUNCTION public.insert_flightsprogram1(v_aircraft_type integer, v_flight_code integer, v_start_date date, v_end_date date) OWNER TO postgres;

--
-- TOC entry 238 (class 1255 OID 159685)
-- Name: insert_gstaff(character varying, character varying, character varying, date, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_gstaff(v_fname character varying, v_lname character varying, v_job character varying, v_birthdate date, v_phone character varying, v_address character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
	v_salary numeric;
BEGIN
        SELECT coalesce(MAX(id),0) FROM gstaff INTO v_id; 
        IF (v_job='Engineer') THEN
		v_salary = 2000;
        ELSE
		v_salary = 1200;
        END IF;
        INSERT INTO gstaff(id, fname, lname, job, birthdate, phone, address, salary) VALUES(v_id+1, v_fname, v_lname, v_job, v_birthdate, v_phone, v_address, v_salary);
END;
$$;


ALTER FUNCTION public.insert_gstaff(v_fname character varying, v_lname character varying, v_job character varying, v_birthdate date, v_phone character varying, v_address character varying) OWNER TO postgres;

--
-- TOC entry 239 (class 1255 OID 159686)
-- Name: insert_gstaff_transaction(integer, integer, action, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_gstaff_transaction(v_fschedule_id integer, v_customer_id integer, v_action action, v_gstaff_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE 
	v_tran_date timestamp;
	v_id integer;
	v_t_id integer;
	v_freeseats integer; 
	v_amount numeric;
	v_trans_time timestamp;
	v_dep_time timestamp;
	cur_fl integer;
	v_dep1 integer;
	v_dest1 integer;
	v_dep2 integer;
	v_dest2 integer;
	old_action action;
	v_dep_country character varying;
	v_dest_country character varying;
BEGIN
	SELECT localtimestamp INTO v_tran_date;
        IF (SELECT COUNT(*) FROM gstaff WHERE id=v_gstaff_id)=0 THEN
		RAISE EXCEPTION 'No gstaff member with id % found.',v_gstaff_id;
	END IF;
	IF (SELECT job FROM gstaff WHERE id=v_gstaff_id)='Engineer' THEN
		RAISE EXCEPTION 'Ground staff % isnt Employee.',v_gstaff_id;
	END IF;
	-- an to action einai cancel, tote apotrepw ston xristi na kanei kapoia sinallagi
	IF v_action='cancel' THEN
		RAISE EXCEPTION 'You can only reserve or buy tickets.';
	END IF;
	-- elegxw an o pelatis exei kanei idi sinallagi gia tin ptisi auti
	SELECT count(*) FROM transactions tr WHERE c_id=v_customer_id AND fschedule_id=v_fschedule_id INTO cur_fl;
	IF cur_fl>0 THEN
		RAISE EXCEPTION 'Customer % has already reserved or bought ticket for flight % .',v_customer_id,v_fschedule_id;
	END IF;   
	-- elegxw an i ptisi pou paei na kanei sinallagi epikaliptetai me kapoia stin opoia exei idi kanei sinallagi
	SELECT price, fdate+dep_time, departure, destination, dep_country, dest_country FROM get_flight_details 
	WHERE fschedule_id=v_fschedule_id INTO v_amount,v_dep_time, v_dep1, v_dest1,v_dep_country, v_dest_country;
	IF EXISTS (SELECT 1 FROM get_trans_details WHERE c_id=v_customer_id AND v_dep_time BETWEEN (fdate+dep_time)-'00:30'::interval AND (fdate+dep_time)+(arr_time-dep_time)+'00:30'::interval) THEN
		RAISE EXCEPTION 'Customer % has a programmed flight in same hour and date.',v_customer_id;
	END IF; 
	IF (SELECT count(*) FROM get_trans_details t1,get_trans_details t2 
	WHERE t1.departure=t2.departure AND t1.fdate=t2.fdate AND t1.c_id=t2.c_id AND t2.c_id=v_customer_id 
	AND t2.fdate=(select fdate from get_flight_details where fschedule_id=v_fschedule_id) AND t2.action<>'cancel') > 0 THEN
		RAISE EXCEPTION 'You cant fly over than one time from the same airport in the same day.';
	END IF;
	-- den mporei na ginei kratisi eisitiriou an perasoun 12 wres prin tin pragmatopoiisi tis ptisis
	IF v_tran_date>=(v_dep_time-'12:00'::interval) AND v_action='reserve' THEN  
		RAISE EXCEPTION 'You cant reserve ticket for flight % .',v_fschedule_id;
	END IF;
	-- den mporei na ginei agora eisitiriou an perasoun 4 wres prin tin pragmatopoiisi tis ptisis
	IF v_tran_date>=(v_dep_time-'04:00'::interval) AND v_action='buy' THEN  
		RAISE EXCEPTION 'You cant buy ticket for flight % .',v_fschedule_id;
	END IF;
	-- pairnw ta dedomena tis kratisis pou exei kanei autos o pelatis tin idia mera
	SELECT t_date, departure, destination, action FROM get_trans_details WHERE c_id=v_customer_id and t_date::date=v_tran_date::date ORDER BY t_date desc LIMIT 1 INTO v_trans_time, v_dep2, v_dest2, old_action;
	IF (v_dest2=v_dep1) AND (v_dest1=v_dep2) AND v_action='buy' AND old_action='buy' THEN
		IF v_dep_country<>'Greece' OR v_dest_country<>'Greece' THEN
			v_amount=v_amount*0.85;
		ELSE
			v_amount=v_amount*0.92;
		END IF;
	END IF;
	SELECT coalesce(MAX(t_id),0) FROM transactions INTO v_id;
	-- get free seats
	SELECT calc_free_seats(v_fschedule_id) INTO v_freeseats;
	-- an to action einai buy kai den yparxoun eleutheres theseis sto aeroplano, tote allazw to action apo buy se reserve
	IF v_action='buy' AND v_freeseats=0 THEN
		v_action='reserve';
	END IF;
	-- insert new transaction in table transactions and table madetransaction
	INSERT INTO transactions(t_id,fschedule_id,c_id,action,t_date) VALUES (v_id+1,v_fschedule_id,v_customer_id,v_action,v_tran_date) RETURNING t_id INTO v_t_id; 
	INSERT INTO madetransaction(id,t_id,type) VALUES (v_gstaff_id, v_t_id, 'gstaff');
	-- an to action einai reserve kai den yparxoun kenes theseis sto aeroplano, tote vazw tin sinallagi auti kai ston pinaka waitinglist
	IF v_action='reserve' AND v_freeseats=0 THEN
		INSERT INTO waitinglist(tid) VALUES (v_t_id);
		RAISE NOTICE 'There arent any free seats for this flight and you have been added to waiting list.';
	END IF;
	-- an to action einai reserve kai yparxoun kenes theseis sto aeroplano, tote vazw tin sinallagi auti kai ston pinaka reservation
	IF v_action='reserve' AND v_freeseats>0 THEN
		INSERT INTO reservation(tid) VALUES (v_t_id);
	END IF;
	-- an to action einai buy kai yparxoun kenes theseis sto aeroplano, tote vazw tin sinallagi auti kai ston pinaka cashier
	IF v_action='buy' AND v_freeseats>0 THEN
		INSERT INTO cashier(tid,amount) VALUES (v_t_id,v_amount); 
	END IF;
END;
$$;


ALTER FUNCTION public.insert_gstaff_transaction(v_fschedule_id integer, v_customer_id integer, v_action action, v_gstaff_id integer) OWNER TO postgres;

--
-- TOC entry 240 (class 1255 OID 159688)
-- Name: insert_language(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_language(v_lang_code character varying, v_name character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	INSERT INTO language(lang_code,name) VALUES (v_lang_code,v_name);
END;
$$;


ALTER FUNCTION public.insert_language(v_lang_code character varying, v_name character varying) OWNER TO postgres;

--
-- TOC entry 241 (class 1255 OID 159689)
-- Name: insert_pilots(character varying, character varying, character varying, date, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_pilots(v_fname character varying, v_lname character varying, v_job character varying, v_birthdate date, v_phone character varying, v_address character varying, v_degree character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
	cnt_pilots integer;
BEGIN
        SELECT coalesce(MAX(id),0) FROM fstaff INTO v_id;
        SELECT COUNT(*) FROM fstaff WHERE job='Pilot' INTO cnt_pilots;
        IF cnt_pilots = 15 THEN
		RAISE EXCEPTION 'You cannot insert anymore pilots.';
        ELSE 
		INSERT INTO fstaff(id, fname, lname, job, birthdate, phone, address) VALUES(v_id+1, v_fname, v_lname, v_job, v_birthdate, v_phone, v_address);
		INSERT INTO fspilots(emp_id, degree) VALUES(v_id+1, v_degree);
        END IF;
END;
$$;


ALTER FUNCTION public.insert_pilots(v_fname character varying, v_lname character varying, v_job character varying, v_birthdate date, v_phone character varying, v_address character varying, v_degree character varying) OWNER TO postgres;

--
-- TOC entry 242 (class 1255 OID 159690)
-- Name: insert_services(integer, integer, timestamp without time zone, integer, integer, smallint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_services(v_emp_id integer, v_aircraft_id integer, v_service_date timestamp without time zone, v_rank integer, v_test_id integer, v_status smallint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	psrank integer;
	stat smallint;
	gs_id integer;
BEGIN
           SELECT status from aircraft where code=v_aircraft_id INTO stat;
	   IF stat=1 THEN
		RAISE EXCEPTION 'The aircraft % can join flights.',v_aircraft_id;
           END IF;
           IF (SELECT COUNT(*) FROM gstaff WHERE id=v_emp_id)=0 THEN
		RAISE EXCEPTION 'No gstaff member with id % found.',v_emp_id;
	   END IF;
	   IF (SELECT job FROM gstaff WHERE id=v_emp_id)='Employee' THEN
		RAISE EXCEPTION 'Ground staff % isnt engineer.',v_emp_id;
	   END IF;
           SELECT pass_rank from authoritytests where testcode=v_test_id INTO psrank;
           IF v_rank < psrank OR v_status=0 THEN
		RAISE EXCEPTION 'The aircraft % doesnt pass the test.',v_aircraft_id;
           ELSE
			INSERT INTO services(emp_id,aircraft_id,service_date,rank,test_id,status) VALUES (v_emp_id,v_aircraft_id,v_service_date,v_rank,v_test_id,v_status);
			UPDATE aircraft SET status=1 WHERE code=v_aircraft_id;
           END IF;
END;
$$;


ALTER FUNCTION public.insert_services(v_emp_id integer, v_aircraft_id integer, v_service_date timestamp without time zone, v_rank integer, v_test_id integer, v_status smallint) OWNER TO postgres;

--
-- TOC entry 259 (class 1255 OID 159691)
-- Name: insert_special_flights(character varying, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_special_flights(v_departure character varying, v_start_date date, v_end_date date) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
res varchar;
v_flights RECORD;
vmax_dep_time time without time zone;
vmax_arr_time time without time zone;
v_flight_id integer;
v_fcode integer;
v_prog_id integer;
v_fschedule_id integer;
v_aircrafts RECORD;
v_fstaff RECORD;
v_msg     TEXT;
v_error_code integer = 0;
v_error_code1 integer = 0;
v_error_code2 integer = 0;
v_error_code3 integer = 0;
v_error_code4 integer = 0;
pil_cnt integer = 0;
att_cnt integer = 0;
v_job character varying;
v_emp_cnt integer;
total_seats numeric = 0;
tot_seats numeric = 0;
tot_wl integer = 0;
scdled integer = 0;

BEGIN -----------------------------------------------1
	res := 'start|' || E'\n';
	BEGIN ----------------------------------------2
		FOR v_flights IN
			select q.fschedule_id, q.cnt_wl, dest_city, dest_shrt, gfd.fdate, gfd.aircraft_type, dep_time, arr_time, departure, destination, price, start_date, end_date 
			from get_flight_details gfd inner join 
			(select fschedule_id, count(*) cnt_wl, fdate
			from get_trans_details gtd inner join waitinglist w on gtd.t_id=w.tid
			where dep_shrt=v_departure and fdate between v_start_date and v_end_date
			group by fschedule_id, fdate) q on gfd.fschedule_id=q.fschedule_id
			order by cnt_wl desc 
			LOOP -------------------------loop1
				-- res := res || 'PAOK 1' || E'\n';
				select (max(dep_time)+'01:00:00'::interval) max_dep_time from get_flight_details
				where fdate=v_flights.fdate and departure=v_flights.departure and destination=v_flights.destination into vmax_dep_time;
				select (vmax_dep_time+(v_flights.arr_time-v_flights.dep_time)) into vmax_arr_time;
				BEGIN-----------------3
					-- res := res || 'PAOK 3' || E'\n';
					-- vazoume tin ptisi sto flight
					SELECT coalesce(MAX(fcode),0) FROM flight INTO v_flight_id;
					INSERT INTO flight(fcode,departure,destination,dep_time,arr_time,price) VALUES 
					(v_flight_id+1,v_flights.departure,v_flights.destination,vmax_dep_time,vmax_arr_time,						v_flights.price) RETURNING fcode INTO v_fcode;

					-- vazoume tin ptisi sto flight days
					INSERT INTO flight_days(fcode,days) VALUES (v_fcode, to_char((case when vmax_arr_time < vmax_dep_time then 
					(v_flights.fdate+vmax_arr_time::interval)+('24:00:00'::interval-vmax_dep_time::interval) 
					else v_flights.fdate+(vmax_arr_time-vmax_dep_time) end),'DY')::days);

					-- vazoume tin ptisi sto flightsprogram
					v_error_code1 := insert_flightsprogram1(v_flights.aircraft_type, v_fcode, v_flights.start_date, v_flights.end_date);
					select program_id from flightsprogram where aircraft_type=v_flights.aircraft_type and flight_code=v_fcode
					and start_date=v_flights.start_date and end_date=v_flights.end_date INTO v_prog_id;

					-- vazoume tin ptisi sto flightschedule
					FOR v_aircrafts IN select code from aircraft where type_id=v_flights.aircraft_type order by code 
					LOOP
						-- res := res || 'PAOK 2' || E'\n';
						BEGIN ----------------------------------------------------------------4
							-- res := res || 'PAOK 4' || E'\n';
                                                        select fschedule_id from flightschedule where aircraft_code=v_aircrafts.code
							and fdate=v_flights.fdate and fprogram_id=v_prog_id INTO v_fschedule_id;
							IF FOUND THEN 
								EXIT;
							END IF;
							v_error_code := insertflightschedule1(v_aircrafts.code, v_flights.fdate, v_prog_id);
							IF v_error_code = 1 THEN
								ROLLBACK;
                                                        ELSE
                                                                scdled = 1;
                                                                v_fschedule_id = v_error_code;
							END IF;
								
							EXCEPTION WHEN others THEN 
								res := res || 'rollback because error on insert in insertflightschedule' || coalesce(v_fschedule_id,0) || '|' || 'fs-error: ' || v_error_code || '|' || 'a_code: ' || v_aircrafts.code || E'\n';
						END; -----------------------------------------------------------------4
					END LOOP;
					IF scdled=0 THEN                                
						v_error_code2 = 50;
					END IF;

					-- vazoume stin ptisi tous ypallilous
                                        pil_cnt = 0;
                                        att_cnt = 0;
					FOR v_fstaff IN SELECT id, job FROM fstaff ORDER BY id
					LOOP						
                                                BEGIN
						--SELECT job FROM fstaff WHERE id=v_fstaff.id INTO v_job;
						IF (v_fstaff.job = 'Pilot' AND pil_cnt < 1) THEN							
							v_error_code3 := insertstaffschedule1(v_fstaff.id,(v_flights.fdate+vmax_dep_time),v_fschedule_id);
                                                        --IF (select count(*) from staffschedule where emp_id=v_fstaff.id and fdate=(v_flights.fdate+vmax_dep_time) 
                                                        --and fschedule_id=v_fschedule_id)>0 THEN
                                                        IF v_error_code3=0 THEN
                                                                pil_cnt = pil_cnt + 1;
                                                        END IF;
						ELSIF (v_fstaff.job = 'Attendant' AND att_cnt < 2) THEN							
							v_error_code3 := insertstaffschedule1(v_fstaff.id,(v_flights.fdate+vmax_dep_time),v_fschedule_id);
                                                        --IF (select count(*) from staffschedule where emp_id=v_fstaff.id and fdate=(v_flights.fdate+vmax_dep_time) 
                                                        --and fschedule_id=v_fschedule_id)>0 THEN
                                                        IF v_error_code3=0 THEN
                                                                att_cnt = att_cnt + 1;
                                                        END IF;
						--ELSE
							--EXIT;
						END IF;                                                
						-- IF v_error_code3 between 1 and 10 THEN
-- 							ROLLBACK;
-- 						END IF;
						IF v_error_code3=-2 THEN
							ROLLBACK;
						END IF;
						SELECT count(*) FROM staffschedule WHERE fdate=(v_flights.fdate+vmax_dep_time) AND fschedule_id=v_fschedule_id INTO v_emp_cnt;
						EXCEPTION WHEN OTHERS THEN
							res := res || 'rollback because error on insert in insertstaffschedule' || '|' || 'v_staff.id: ' || v_fstaff.id || '|' ||  'pil_cnt: ' || pil_cnt || '|' || 'att_cnt: ' || att_cnt || ' | error3: ' || v_error_code3 || ' | date :' || v_flights.fdate+vmax_dep_time || ' | fsch_id: ' || v_fschedule_id || ' | ' || coalesce(v_emp_cnt,0) || E'\n';
						END;
					END LOOP;
					IF v_emp_cnt < 3 THEN
						v_error_code4 = 60;
					END IF;

					IF v_error_code1 = 31 THEN
						ROLLBACK;
					ELSIF v_error_code = 1 THEN
						ROLLBACK;
					ELSIF v_error_code2 = 50 THEN
						ROLLBACK;
					ELSIF v_error_code4 = 60 THEN
						ROLLBACK;
					END IF;
					EXCEPTION WHEN others THEN
						res := res || 'rollback because error somewhere' || ' | ' || v_error_code || ' | ' || v_error_code1 || ' | ' || v_error_code2 || ' | ' || v_error_code4 || ' | ' || E'\n';
					
				END;-----------------3
				-- vriskoume ton arithmo thesewn twn aeroskafwn gia tis ptiseis pou mporoun na pragmatopoihthoun
				select num_seats from aircraft_type art inner join get_flight_details gfd on art.id=gfd.aircraft_type 
				where gfd.fschedule_id=v_fschedule_id into tot_seats;
				total_seats := total_seats + tot_seats;
				-- vriskoume ton sinoliko arithmo twn pelatwn pou einai sto waiting list
				tot_wl := tot_wl + v_flights.cnt_wl;
				
			END LOOP;--------------------loop1
			--akyrwsh olhs ths syndiallaghs                           
			IF tot_wl < total_seats*0.50 THEN
				ROLLBACK;
			END IF;
			EXCEPTION WHEN OTHERS THEN
				res := res || 'rollback all' || E'\n';
			
	END;-----------------------------------------2
	res := res || 'end' || '|' || E'\n';
	RETURN res;
END;-------------------------------------------------1
$$;


ALTER FUNCTION public.insert_special_flights(v_departure character varying, v_start_date date, v_end_date date) OWNER TO postgres;

--
-- TOC entry 243 (class 1255 OID 159693)
-- Name: insert_spoken_langs(integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_spoken_langs(v_id integer, v_otherlangs character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
        INSERT INTO spoken_langs(emp_id, lang_code) SELECT v_id, v_otherlangs WHERE EXISTS (SELECT emp_id FROM fsattendant WHERE emp_id=v_id);
END;
$$;


ALTER FUNCTION public.insert_spoken_langs(v_id integer, v_otherlangs character varying) OWNER TO postgres;

--
-- TOC entry 244 (class 1255 OID 159694)
-- Name: insert_travelagency(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insert_travelagency(v_name character varying, v_phone character varying, v_address character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_id integer;
	cnt_trag integer;
BEGIN
        SELECT coalesce(MAX(id),0) FROM travelagency INTO v_id; 
	SELECT COUNT(*) FROM travelagency INTO cnt_trag;
        IF cnt_trag = 5 THEN
		RAISE EXCEPTION 'You cannot insert anymore travel agencies.';
        ELSE 
		INSERT INTO travelagency(id, name, phone, address) VALUES(v_id+1, v_name, v_phone, v_address);
	END IF;
END;
$$;


ALTER FUNCTION public.insert_travelagency(v_name character varying, v_phone character varying, v_address character varying) OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 159695)
-- Name: insertflight_done(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insertflight_done(id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE 
	dr time;
	atype integer;
	tot_hr numeric;
	min_dr numeric;
	v_dep_dt_tm timestamp without time zone;
BEGIN
	SELECT CAST(f.arr_time - f.dep_time AS time) mytime, aircraft_type, (fs.fdate+f.dep_time) dep_dt_tm FROM flight f 
	INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
	INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
	WHERE fs.fschedule_id=id INTO dr, atype, v_dep_dt_tm;
	IF (v_dep_dt_tm + dr) > localtimestamp THEN
		RAISE EXCEPTION 'Flight % has not been made yet.', id;
	END IF;
	INSERT INTO flightdone (fschedule_id, duration) VALUES (id, dr);
	UPDATE aircraft SET total_hours=total_hours+(flight_hours(dr)/60) WHERE code=(SELECT aircraft_code FROM flightschedule WHERE fschedule_id=id) RETURNING total_hours INTO tot_hr;
	SELECT min(flight_hours((arr_time-dep_time)::time))/60 FROM flight f INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code inner join flightschedule fs on fp.program_id=fs.fprogram_id INTO min_dr;
	IF tot_hr=150 OR tot_hr=150-(min_dr*2) THEN
		UPDATE aircraft SET status=0 WHERE code=(SELECT aircraft_code FROM flightschedule WHERE fschedule_id=id);
	END IF;
END;
$$;


ALTER FUNCTION public.insertflight_done(id integer) OWNER TO postgres;

--
-- TOC entry 222 (class 1255 OID 159696)
-- Name: insertflightschedule(integer, date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insertflightschedule(a_code integer, fl_date date, prog_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_dr numeric;
	v_sc_hr numeric;
	v_t_hr numeric;
	v_cnt_hr numeric;
	v_dep_city character varying;
	cntr character varying;
	air_type character varying;
	v_fsid integer;
	v_dp_time time;
        fl_count integer;
        start_dt date;
        end_dt date;
        day_1 character varying[];
        day_2 character varying;
        air_exists integer;
BEGIN
	IF (SELECT count(*) FROM aircraft WHERE code=a_code)=0 THEN
		RAISE EXCEPTION 'There isnt an aircraft with code % .',a_code;
	END IF;
	IF (SELECT count(*) FROM flightsprogram WHERE program_id=prog_id)=0 THEN
		RAISE EXCEPTION 'There isnt programmed flight with id % .',prog_id;
	END IF;
	SELECT coalesce(MAX(fschedule_id),0) FROM flightschedule INTO v_fsid;
	SELECT city FROM airport a INNER JOIN flight f ON a.code=f.departure INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code WHERE fp.program_id=prog_id INTO v_dep_city;
        IF v_dep_city<>'Athens' THEN
		RAISE EXCEPTION 'You must insert a basic flight.';
        END IF;
	-- pairnw tin diarkeia tis ptisis
	SELECT flight_hours(CAST(f.arr_time - f.dep_time AS time))/60 f_hours, f.dep_time FROM flight f 
        INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
        WHERE program_id=prog_id INTO v_dr, v_dp_time;
	-- pairnw tis sinolikes wres pou exoun programmatistei
	SELECT coalesce(SUM(flight_hours(CAST(f.arr_time - f.dep_time AS time))/60),0) sch_hours FROM flight f 
	INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
	INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
	WHERE NOT EXISTS (SELECT * FROM flightdone WHERE fschedule_id=fs.fschedule_id) AND fs.aircraft_code=a_code INTO v_sc_hr;
	-- Check if an aircraft is in another flight in same day and hour
        SELECT count(*) FROM flight f 
        INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
        INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
        WHERE aircraft_code=a_code AND fdate=fl_date AND fl_date+f.dep_time BETWEEN (fl_date+(v_dp_time-'00:30'::interval)) 
        AND fl_date+v_dp_time+((f.arr_time-f.dep_time)*2)+'01:00'::interval INTO fl_count;
        -- Check if the flight date is the same with flight date from flightsprogram
        SELECT start_date, end_date FROM flightsprogram WHERE program_id=prog_id INTO start_dt, end_dt;
        SELECT array(SELECT days FROM flight_days fd WHERE fcode=(select flight_code from flightsprogram where program_id=prog_id)) INTO day_1;
        SELECT to_char(fl_date,'DY') INTO day_2;
        -- Check if the aircraft you try to insert belongs to the right type	
        IF a_code NOT IN (SELECT code FROM aircraft a INNER JOIN aircraft_type atp ON a.type_id=atp.id INNER JOIN flightsprogram fp ON atp.id=fp.aircraft_type 
        WHERE program_id=prog_id) THEN
                RAISE EXCEPTION 'Aircraft % is different type.',a_code;
        END IF;
        -- Check if flight exists on schedule
        SELECT 1 FROM flightschedule WHERE fprogram_id=prog_id AND fdate=fl_date INTO air_exists;
           IF fl_date NOT BETWEEN start_dt AND end_dt THEN
                RAISE EXCEPTION 'The flight % isnt available at date %.',prog_id,fl_date;
           END IF;
           IF day_2 NOT IN (select(unnest(day_1))) THEN
                RAISE EXCEPTION 'This flight isnt available on % .',day_2;
           END IF;
           IF air_exists=1 THEN
                RAISE EXCEPTION 'Flight % is already scheduled at % date.',prog_id,fl_date;
           END IF; 
            IF fl_count>1 THEN
                RAISE EXCEPTION 'Aircraft % is in another flight in the same hour and day', a_code;
           END IF;
	-- pairnw tis sinolikes wres ptisis pou exoun pragmatopoihthei
	SELECT total_hours FROM aircraft WHERE code=a_code INTO v_t_hr;
	-- elegxw an tha kseperasei tis 150 wres
	v_cnt_hr=(v_t_hr+v_sc_hr);
	IF (((v_dr*2)+v_cnt_hr) > 150.0000000000000000) THEN
		RAISE EXCEPTION 'Aircraft % has reached the limit of 150 flight hours.Total hours % . Flight hours % .', a_code, round(v_cnt_hr,2), round((dr*2),2);
	END IF;
	SELECT ar.country FROM airport ar,    
        (SELECT * FROM airport a INNER JOIN flight f ON a.code=f.departure AND city='Athens') x
        WHERE ar.code=x.destination AND x.fcode=(SELECT flight_code FROM flightsprogram WHERE program_id=prog_id) INTO cntr; 
	SELECT type FROM aircraft_type airtype WHERE airtype.id=(SELECT type_id FROM aircraft WHERE code=a_code) INTO air_type; 
	IF air_type='Boeing737' THEN 
		IF cntr='Greece' THEN
			INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (v_fsid+1, a_code, fl_date, prog_id);
			-- INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (v_fsid+2, a_code, fl_date, prog_id+1);
		ELSE
			RAISE EXCEPTION 'Aircraft % cannot join international flights.',a_code;
		END IF;
	ELSE
		INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (v_fsid+1, a_code, fl_date, prog_id);
		-- INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (v_fsid+2, a_code, fl_date, prog_id+1);
	END IF;
	RETURN;
END;
$$;


ALTER FUNCTION public.insertflightschedule(a_code integer, fl_date date, prog_id integer) OWNER TO postgres;

--
-- TOC entry 246 (class 1255 OID 159698)
-- Name: insertflightschedule1(integer, date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insertflightschedule1(a_code integer, fl_date date, prog_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_dr numeric;
	v_sc_hr numeric;
	v_t_hr numeric;
	v_cnt_hr numeric;
	v_dep_city character varying;
	cntr character varying;
	air_type character varying;
	v_fsid integer;
	v_dp_time time;
        fl_count_1 integer;
        fl_count_2 integer;
        start_dt date;
        end_dt date;
        day_1 character varying[];
        day_2 character varying;
        air_exists integer = 0;
        r_err_code integer = 0;
        v_ret_id integer;
BEGIN
	BEGIN
                IF (SELECT count(*) FROM aircraft WHERE code=a_code)=0 THEN
                        ROLLBACK;                        
                END IF;

                IF (SELECT count(*) FROM flightsprogram WHERE program_id=prog_id)=0 THEN
                        ROLLBACK;
                END IF;
                
                SELECT coalesce(MAX(fschedule_id),0) FROM flightschedule INTO v_fsid;
                SELECT city FROM airport a INNER JOIN flight f ON a.code=f.departure INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code WHERE fp.program_id=prog_id INTO v_dep_city;
                IF v_dep_city<>'Athens' THEN
                        ROLLBACK;
                END IF;

                -- pairnw tin diarkeia tis ptisis
                SELECT flight_hours(CAST(f.arr_time - f.dep_time AS time))/60 f_hours, f.dep_time FROM flight f 
                INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
                WHERE program_id=prog_id INTO v_dr, v_dp_time;
                -- pairnw tis sinolikes wres pou exoun programmatistei
                SELECT coalesce(SUM(flight_hours(CAST(f.arr_time - f.dep_time AS time))/60),0) sch_hours FROM flight f 
                INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
                INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
                WHERE NOT EXISTS (SELECT * FROM flightdone WHERE fschedule_id=fs.fschedule_id) AND fs.aircraft_code=a_code INTO v_sc_hr;
                -- Check if an aircraft is in another flight in same day and hour
                SELECT count(*) FROM flight f 
                INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
                INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
                WHERE aircraft_code=a_code AND fdate=fl_date AND fl_date+f.dep_time BETWEEN (fl_date+(v_dp_time-'00:30'::interval)) 
                AND fl_date+v_dp_time+(f.arr_time-f.dep_time) INTO fl_count_1;

		--
		SELECT count(*) FROM flight f 
                INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
                INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
                WHERE aircraft_code=a_code AND fdate=fl_date AND fl_date+f.arr_time BETWEEN (fl_date+(v_dp_time-'00:30'::interval)) 
                AND fl_date+v_dp_time+(f.arr_time-f.dep_time) INTO fl_count_2;
                
                -- Check if the flight date is the same with flight date from flightsprogram
                SELECT start_date, end_date FROM flightsprogram WHERE program_id=prog_id INTO start_dt, end_dt;
                SELECT array(SELECT days FROM flight_days fd WHERE fcode=(select flight_code from flightsprogram where program_id=prog_id)) INTO day_1;
                SELECT to_char(fl_date,'DY') INTO day_2;
                -- Check if the aircraft you try to insert belongs to the right type	
                IF a_code NOT IN (SELECT code FROM aircraft a INNER JOIN aircraft_type atp ON a.type_id=atp.id INNER JOIN flightsprogram fp ON atp.id=fp.aircraft_type 
                WHERE program_id=prog_id) THEN
                        ROLLBACK;
                END IF;

                -- Check if flight exists on schedule
                SELECT 1 FROM flightschedule WHERE fprogram_id=prog_id AND fdate=fl_date INTO air_exists;
                IF fl_date NOT BETWEEN start_dt AND end_dt THEN
                        ROLLBACK;
                END IF;

                IF day_2 NOT IN (select(unnest(day_1))) THEN
                        ROLLBACK;
                END IF;

                IF air_exists=1 THEN
                        ROLLBACK;
                END IF;

                IF fl_count_1>0 OR fl_count_2>0 THEN
                        ROLLBACK;
                END IF;

                -- pairnw tis sinolikes wres ptisis pou exoun pragmatopoihthei
                SELECT total_hours FROM aircraft WHERE code=a_code INTO v_t_hr;
                -- elegxw an tha kseperasei tis 150 wres
                v_cnt_hr=(v_t_hr+v_sc_hr);
                IF (((v_dr)+v_cnt_hr) > 150.0000000000000000) THEN
                        ROLLBACK;
                END IF;

                SELECT ar.country FROM airport ar,    
                (SELECT * FROM airport a INNER JOIN flight f ON a.code=f.departure AND city='Athens') x
                WHERE ar.code=x.destination AND x.fcode=(SELECT flight_code FROM flightsprogram WHERE program_id=prog_id) INTO cntr; 
                SELECT type FROM aircraft_type airtype WHERE airtype.id=(SELECT type_id FROM aircraft WHERE code=a_code) INTO air_type; 
                IF air_type='Boeing737' THEN 
                        IF cntr='Greece' THEN
                                INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (v_fsid+1, a_code, fl_date, prog_id) RETURNING fschedule_id INTO v_ret_id;
                        ELSE
                                ROLLBACK;
                        END IF;
                ELSE
                        INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (v_fsid+1, a_code, fl_date, prog_id) RETURNING fschedule_id INTO v_ret_id;
                END IF;
                r_err_code = v_ret_id;
		EXCEPTION WHEN others THEN
                        r_err_code = 1;
            
        END;
		
	RETURN r_err_code;
END;
$$;


ALTER FUNCTION public.insertflightschedule1(a_code integer, fl_date date, prog_id integer) OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 159699)
-- Name: insertstaffschedule(integer, timestamp without time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insertstaffschedule(empid integer, fl_date timestamp without time zone, fsch_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE 
	dp_time time;
	ar_time time;
	fl_count integer;
	ispilot smallint;
	isattendant smallint;
	v_dep_city character varying;
	dr numeric;
	sc_hr numeric;
	sch_aircraft integer;
	exp_aircrafts integer[];
	c_pil integer;
        c_att integer;
        str_dt date;
BEGIN
	IF (SELECT count(*) FROM fstaff WHERE id=empid)=0 THEN
		RAISE EXCEPTION 'There isnt flight staff employee with id % .',empid;
	END IF;
	SELECT city FROM airport a INNER JOIN flight f ON a.code=f.departure INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code inner join flightschedule fs on fp.program_id=fs.fprogram_id WHERE fs.fschedule_id=fsch_id INTO v_dep_city;
        IF v_dep_city<>'Athens' THEN
		RAISE EXCEPTION 'You must insert a basic flight.';
        END IF;
        select flight_hours(cast(f.arr_time - f.dep_time as time))/60 f_hours from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	where fs.fschedule_id=fsch_id INTO dr;
	
	select f.dep_time,f.arr_time from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	where fs.fschedule_id=fsch_id INTO dp_time,ar_time; 
	-- check if emp is pilot or attendant
	select 1 from fspilots where emp_id=empid INTO ispilot;
	select 1 from fsattendant where emp_id=empid INTO isattendant;
	-- Check if the flight date is the same with flight date from flightschedule
        SELECT fdate FROM flightschedule WHERE fschedule_id=fsch_id INTO str_dt;
        IF (fl_date::date)<>str_dt THEN
                RAISE EXCEPTION 'The flight % isnt available at date %.',fsch_id,fl_date;
        END IF;
        -- Check if a pilot is scheduled for this flight
        select count(*) from staffschedule ss inner join fspilots pil on ss.emp_id=pil.emp_id where fschedule_id=fsch_id INTO c_pil;
        select count(*) from staffschedule ss inner join fsattendant att on ss.emp_id=att.emp_id where fschedule_id=fsch_id INTO c_att;
        IF (c_pil=1) AND (ispilot=1) THEN
                RAISE EXCEPTION 'A pilot is already scheduled for flight %', fsch_id;
        END IF;
        IF (c_att=2) AND (isattendant=1) THEN
                RAISE EXCEPTION 'Attendants are already scheduled for flight %', fsch_id;
        END IF;
	-- elegxoume an o pilotos pou vazoume mporei na petaksei auton ton typo aeroskafous pou tha ektelesei tin ptisi
	SELECT aircraft_type FROM get_flight_details WHERE fschedule_id=fsch_id INTO sch_aircraft;
	IF ispilot=1 THEN
		SELECT array(SELECT aircraft_type FROM expertise WHERE emp_id=empid) INTO exp_aircrafts;
		IF sch_aircraft NOT IN (SELECT(unnest(exp_aircrafts))) THEN
			RAISE EXCEPTION 'Pilot % cannot fly aircraft type % .',empid, sch_aircraft;
		END IF; 
        END IF;
	-- elegxw an o ypallilos einai se alli ptisi tin idia mera kai wra
	select count(*) from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where emp_id=empid and ss.fdate between (fl_date-'00:30'::interval) and (fl_date+((ar_time-dp_time)*2)+'01:00'::interval) INTO fl_count;
	IF (fl_count>0) AND (ispilot=1) THEN
		RAISE EXCEPTION 'Pilot % is in another flight in the same hour and day.', empid;
        END IF; 
        IF (fl_count>0) AND (isattendant=1) THEN
		RAISE EXCEPTION 'Attendant % is in another flight in the same hour and day.', empid;
        END IF;
	
	-- get flight staff flight hours
	select coalesce(sum(flight_hours(cast(f.arr_time - f.dep_time as time)))/60,0) mytime from flight f inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where fs.fdate between (date_trunc('week', (fl_date)::timestamp)::date) and ((date_trunc('week', (fl_date)::timestamp)+ '6 days'::interval)::date) and ss.emp_id=empid INTO sc_hr;
	IF (ispilot=1) AND ((dr*2)+sc_hr > 25) THEN
		RAISE EXCEPTION 'Pilot % reached the limit of 25 weekly flight hours. Total hours % . Flight hours % .', empid, round(sc_hr,2), round((dr*2),2);
	END IF;
	IF (isattendant=1) AND ((dr*2)+sc_hr > 35) THEN
		RAISE EXCEPTION 'Attendant % reached the limit of 35 weekly flight hours. Total hours % . Flight hours % .', empid, round(sc_hr,2), round((dr*2),2);
	END IF;
	INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (empid, fl_date, fsch_id);
	-- INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (empid, fl_date+(ar_time-dp_time)+'00:30'::interval, fsch_id+1);
	RETURN;
END;
$$;


ALTER FUNCTION public.insertstaffschedule(empid integer, fl_date timestamp without time zone, fsch_id integer) OWNER TO postgres;

--
-- TOC entry 258 (class 1255 OID 159700)
-- Name: insertstaffschedule1(integer, timestamp without time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION insertstaffschedule1(empid integer, fl_date timestamp without time zone, fsch_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
	dp_time time;
	ar_time time;
	fl_count_1 integer = 0;
        fl_count_2 integer = 0;
	ispilot smallint;
	isattendant smallint;
	v_dep_city character varying;
	dr numeric;
	sc_hr numeric;
	sch_aircraft integer;
	exp_aircrafts integer[];
	c_pil integer = 0;
        c_att integer = 0;
        str_dt date;
        s_err_code integer = 0;
        q_err_code integer = 0;
BEGIN
BEGIN
	IF (SELECT count(*) FROM fstaff WHERE id=empid)=0 THEN
		--q_err_code = 1;
                ROLLBACK;
		--RAISE EXCEPTION 'There isnt flight staff employee with id % .',empid;
	END IF;
	
	SELECT city FROM airport a INNER JOIN flight f ON a.code=f.departure INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code inner join flightschedule fs on fp.program_id=fs.fprogram_id WHERE fs.fschedule_id=fsch_id INTO v_dep_city;
        IF v_dep_city<>'Athens' THEN
		--q_err_code = 2;
                ROLLBACK;
		--RAISE EXCEPTION 'You must insert a basic flight.';
        END IF;
        
        select flight_hours(cast(f.arr_time - f.dep_time as time))/60 f_hours from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	where fs.fschedule_id=fsch_id INTO dr;
	
	select f.dep_time,f.arr_time from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	where fs.fschedule_id=fsch_id INTO dp_time,ar_time; 
	-- check if emp is pilot or attendant
	select 1 from fspilots where emp_id=empid INTO ispilot;
	select 1 from fsattendant where emp_id=empid INTO isattendant;
	-- Check if the flight date is the same with flight date from flightschedule
        SELECT fdate FROM flightschedule WHERE fschedule_id=fsch_id INTO str_dt;
        IF (fl_date::date)<>str_dt THEN
		--q_err_code = 3;
                ROLLBACK;
                --RAISE EXCEPTION 'The flight % isnt available at date %.',fsch_id,fl_date;
        END IF;
        
        -- Check if a pilot is scheduled for this flight
        select count(*) from staffschedule ss inner join fspilots pil on ss.emp_id=pil.emp_id where fschedule_id=fsch_id INTO c_pil;
        select count(*) from staffschedule ss inner join fsattendant att on ss.emp_id=att.emp_id where fschedule_id=fsch_id INTO c_att;
        IF (c_pil=1) AND (ispilot=1) THEN
                --q_err_code = 4;
                ROLLBACK;
                --RAISE EXCEPTION 'A pilot is already scheduled for flight %', fsch_id;
        END IF;
        IF (c_att=2) AND (isattendant=1) THEN
		--q_err_code = 5;
                ROLLBACK;
                --RAISE EXCEPTION 'Attendants are already scheduled for flight %', fsch_id;
        END IF;
        
	-- elegxoume an o pilotos pou vazoume mporei na petaksei auton ton typo aeroskafous pou tha ektelesei tin ptisi
	SELECT aircraft_type FROM get_flight_details WHERE fschedule_id=fsch_id INTO sch_aircraft;
	IF ispilot=1 THEN
		SELECT array(SELECT aircraft_type FROM expertise WHERE emp_id=empid) INTO exp_aircrafts;
		IF sch_aircraft NOT IN (SELECT(unnest(exp_aircrafts))) THEN
			--q_err_code = 6;
                        ROLLBACK;
			--RAISE EXCEPTION 'Pilot % cannot fly aircraft type % .',empid, sch_aircraft;
		END IF; 
        END IF;
        
	-- elegxw an o ypallilos einai se alli ptisi tin idia mera kai wra
	select count(*) from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where emp_id=empid and ss.fdate between (fl_date-'00:30'::interval) and (fl_date+(ar_time-dp_time)) INTO fl_count_1;
        --
        select count(*) from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where emp_id=empid and ss.fdate+'01:00'::interval between (fl_date-'00:30'::interval) and (fl_date+(ar_time-dp_time)) INTO fl_count_2;
	IF (fl_count_1>0 or fl_count_2>0) AND (ispilot=1) THEN
		--q_err_code = 7;
                ROLLBACK;
		--RAISE EXCEPTION 'Pilot % is in another flight in the same hour and day.', empid;
        END IF; 
        IF (fl_count_1>0 or fl_count_2>0) AND (isattendant=1) THEN
		--q_err_code = 8;
                ROLLBACK;
		--RAISE EXCEPTION 'Attendant % is in another flight in the same hour and day.', empid;
        END IF;
	
	-- get flight staff flight hours
	select coalesce(sum(flight_hours(cast(f.arr_time - f.dep_time as time)))/60,0) mytime from flight f inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where fs.fdate between (date_trunc('week', (fl_date)::timestamp)::date) and ((date_trunc('week', (fl_date)::timestamp)+ '6 days'::interval)::date) and ss.emp_id=empid INTO sc_hr;
	IF (ispilot=1) AND ((dr)+sc_hr > 25) THEN
		--q_err_code = 9;
                ROLLBACK;
		--RAISE EXCEPTION 'Pilot % reached the limit of 25 weekly flight hours. Total hours % . Flight hours % .', empid, round(sc_hr,2), round((dr*2),2);
	END IF;
	IF (isattendant=1) AND ((dr)+sc_hr > 35) THEN
		--q_err_code = 10;
                ROLLBACK;
		--RAISE EXCEPTION 'Attendant % reached the limit of 35 weekly flight hours. Total hours % . Flight hours % .', empid, round(sc_hr,2), round((dr*2),2);
	END IF;
        
	--IF q_err_code=0 THEN
                INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (empid, fl_date, fsch_id);
        --END IF;
	EXCEPTION WHEN others THEN
                       q_err_code=-2;
END;
	RETURN q_err_code;
END;
$$;


ALTER FUNCTION public.insertstaffschedule1(empid integer, fl_date timestamp without time zone, fsch_id integer) OWNER TO postgres;

--
-- TOC entry 248 (class 1255 OID 159702)
-- Name: retr_1(character varying, character varying, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION retr_1(v_departure character varying, v_destination character varying, v_fdate date, OUT v_fl_code integer, OUT v_price numeric, OUT v_fr_seats integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	return query SELECT fschedule_id, price, calc_free_seats(fschedule_id) from get_flight_details where dep_shrt=v_departure and dest_shrt=v_destination and fdate=v_fdate;
END;
$$;


ALTER FUNCTION public.retr_1(v_departure character varying, v_destination character varying, v_fdate date, OUT v_fl_code integer, OUT v_price numeric, OUT v_fr_seats integer) OWNER TO postgres;

--
-- TOC entry 249 (class 1255 OID 159703)
-- Name: retr_2(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION retr_2(v_departure character varying, v_destination character varying, OUT v_start_fsc_id integer, OUT v_start_fdate timestamp without time zone, OUT v_start_dep_time time without time zone, OUT v_start_arr_time time without time zone, OUT v_tot_price numeric, OUT v_fr_seats integer, OUT v_start_city character varying, OUT v_end_city character varying, OUT v_end_fsc_id integer, OUT v_end_fdate date, OUT v_end_dep_time time without time zone, OUT v_end_arr_time time without time zone, OUT v_tot_air_dr interval, OUT v_dr_station interval, OUT v_total_dr interval) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF v_departure='ATH' OR v_destination='ATH' THEN
		RAISE EXCEPTION 'You can search only for combine flights. This flight is a direct flight.';
	END IF;
	DROP TABLE IF EXISTS temp1;
	DROP TABLE IF EXISTS temp2;
	CREATE TEMP TABLE temp1 AS
	select *, calc_free_seats(fschedule_id) free_seats, (fdate+dep_time) fl_time from get_flight_details where dep_shrt=v_departure order by fdate, dep_time;
	CREATE TEMP TABLE temp2 AS
	select *, calc_free_seats(fschedule_id) free_seats, (fdate+dep_time) fl_time from get_flight_details where dest_shrt=v_destination order by fdate, dep_time;
	
	return query select x.*
	,(x.end_fdate+x.end_dep_time)-(case when x.start_arr_time < x.start_dep_time then ((x.start_fdate+x.start_arr_time::interval)+('24:00:00'::interval-x.start_dep_time::interval)) 
	else (x.start_fdate::date+x.start_arr_time) end) dr_stasis
	,((x.end_fdate+x.end_dep_time)-(case when x.start_arr_time < x.start_dep_time then ((x.start_fdate+x.start_arr_time::interval)+('24:00:00'::interval-x.start_dep_time::interval)) 
	else (x.start_fdate::date+x.start_arr_time) end)) + x.tot_air_dr tot_dr
	from 
	(
		select 
		t1.fschedule_id start_fsch_id 
		,t1.fl_time start_fdate 
		--,t1.departure start_dep 
		--,t1.destination start_dest 
		,t1.dep_time start_dep_time
		,t1.arr_time start_arr_time
		,(t1.price+t2.price) tot_price
		,case when t1.free_seats<t2.free_seats then t1.free_seats else t2.free_seats end free_seats
		,t1.dep_city start_city, t2.dest_city end_city, t2.fschedule_id end_fsch_id
		,case when t1.arr_time < t1.dep_time then ((t2.fl_time+t2.arr_time::interval)+('24:00:00'::interval-t2.dep_time::interval))::date else t2.fdate end end_fdate
		,t2.dep_time end_dep_time, t2.arr_time end_arr_time
		,((t1.arr_time-t1.dep_time)::time)::interval+((t2.arr_time-t2.dep_time)::time)::interval tot_air_dr
		from temp1 t1, temp2 t2
		where t1.destination=t2.departure and (t2.fl_time) BETWEEN ((t1.fl_time)+(t1.arr_time-t1.dep_time)+'01:00'::interval) AND ((t1.fl_time)+(t1.arr_time-t1.dep_time)+'2 days'::interval)
		order by start_fdate, start_dep_time, end_fdate, end_dep_time
	) x;
END;
$$;


ALTER FUNCTION public.retr_2(v_departure character varying, v_destination character varying, OUT v_start_fsc_id integer, OUT v_start_fdate timestamp without time zone, OUT v_start_dep_time time without time zone, OUT v_start_arr_time time without time zone, OUT v_tot_price numeric, OUT v_fr_seats integer, OUT v_start_city character varying, OUT v_end_city character varying, OUT v_end_fsc_id integer, OUT v_end_fdate date, OUT v_end_dep_time time without time zone, OUT v_end_arr_time time without time zone, OUT v_tot_air_dr interval, OUT v_dr_station interval, OUT v_total_dr interval) OWNER TO postgres;

--
-- TOC entry 250 (class 1255 OID 159704)
-- Name: retr_3(character varying, character varying, date, time without time zone, time without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION retr_3(v_departure character varying, v_destination character varying, v_fdate date, v_time1 time without time zone, v_time2 time without time zone, OUT v_free_seats integer, OUT v_fschedule_id integer, OUT v_fldate date, OUT v_fldep_time time without time zone, OUT v_arr_time time without time zone, OUT v_price numeric, OUT v_dep_city character varying, OUT v_dest_city character varying) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF v_time1 >= v_time2 THEN
		RAISE EXCEPTION 'Time 2 must be bigger than time 1';
	END IF;
	return query SELECT calc_free_seats(fschedule_id), fschedule_id, fdate, dep_time, arr_time, price, dep_city, dest_city from get_flight_details 
	where dep_shrt=v_departure and dest_shrt=v_destination and fdate=v_fdate and dep_time BETWEEN v_time1 AND v_time2 ORDER BY fdate, dep_time;
END;
$$;


ALTER FUNCTION public.retr_3(v_departure character varying, v_destination character varying, v_fdate date, v_time1 time without time zone, v_time2 time without time zone, OUT v_free_seats integer, OUT v_fschedule_id integer, OUT v_fldate date, OUT v_fldep_time time without time zone, OUT v_arr_time time without time zone, OUT v_price numeric, OUT v_dep_city character varying, OUT v_dest_city character varying) OWNER TO postgres;

--
-- TOC entry 251 (class 1255 OID 159705)
-- Name: retr_4(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION retr_4(v_fdate date, OUT v_free_seats integer, OUT v_fschedule_id integer, OUT v_fldate date, OUT v_fldep_time time without time zone, OUT v_arr_time time without time zone, OUT v_price numeric, OUT v_dep_city character varying, OUT v_dest_city character varying) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	return query SELECT calc_free_seats(fschedule_id), fschedule_id, fdate, dep_time, arr_time, price, dep_city, dest_city from get_flight_details where fdate BETWEEN v_fdate AND v_fdate+'7'::integer AND dep_country='Greece' and dest_country<>'Greece';
END;
$$;


ALTER FUNCTION public.retr_4(v_fdate date, OUT v_free_seats integer, OUT v_fschedule_id integer, OUT v_fldate date, OUT v_fldep_time time without time zone, OUT v_arr_time time without time zone, OUT v_price numeric, OUT v_dep_city character varying, OUT v_dest_city character varying) OWNER TO postgres;

--
-- TOC entry 252 (class 1255 OID 159706)
-- Name: retr_5(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION retr_5(v_fcode integer, OUT v_fname character varying, OUT v_lname character varying, OUT v_phone character varying, OUT v_action action, OUT v_fschedule_id integer, OUT v_flight_code integer, OUT v_price numeric, OUT v_fdate date, OUT v_dep_time time without time zone, OUT v_arr_time time without time zone, OUT v_dep_city character varying, OUT v_dest_city character varying) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	return query select fname,lname,phone,action,fschedule_id,flight_code,price,fdate,dep_time,arr_time,dep_city,dest_city from get_trans_details t inner join waitinglist w on t.t_id=w.tid inner join customer c on t.c_id=c.id where flight_code=v_fcode and action='reserve' order by t_date limit 5; 
END;
$$;


ALTER FUNCTION public.retr_5(v_fcode integer, OUT v_fname character varying, OUT v_lname character varying, OUT v_phone character varying, OUT v_action action, OUT v_fschedule_id integer, OUT v_flight_code integer, OUT v_price numeric, OUT v_fdate date, OUT v_dep_time time without time zone, OUT v_arr_time time without time zone, OUT v_dep_city character varying, OUT v_dest_city character varying) OWNER TO postgres;

--
-- TOC entry 253 (class 1255 OID 159707)
-- Name: retr_6(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION retr_6(v_emp_id integer, OUT v_employee integer, OUT v_employee_name text, OUT v_scheduled_flight integer, OUT v_departure_date timestamp without time zone, OUT v_arrival_date timestamp without time zone, OUT v_departure_city character varying, OUT v_destination_city character varying) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY SELECT ss.emp_id v_employee,fst.fname || ' ' || fst.lname v_employee_name,ss.fschedule_id v_scheduled_flight,ss.fdate v_departure_date,
	case when v.arr_time < v.dep_time then (ss.fdate+v.arr_time::interval)+('24:00:00'::interval-v.dep_time::interval) else ss.fdate+(v.arr_time-v.dep_time) end v_arrival_date,v.dep_city v_departure_city,v.dest_city v_destination_city FROM staffschedule ss INNER JOIN fstaff fst ON ss.emp_id=fst.id INNER JOIN get_flight_details v ON ss.fschedule_id=v.fschedule_id WHERE emp_id=v_emp_id ORDER BY ss.fdate;
END;
$$;


ALTER FUNCTION public.retr_6(v_emp_id integer, OUT v_employee integer, OUT v_employee_name text, OUT v_scheduled_flight integer, OUT v_departure_date timestamp without time zone, OUT v_arrival_date timestamp without time zone, OUT v_departure_city character varying, OUT v_destination_city character varying) OWNER TO postgres;

--
-- TOC entry 254 (class 1255 OID 159708)
-- Name: update_fsmonthsalary(integer, smallint, smallint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_fsmonthsalary(v_fs_id integer, v_month smallint, v_year smallint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
ispilot integer;
isattendant integer;
v_id integer;
v_job character varying;
v_domestic_hr numeric;
v_international_hr numeric;
tot_salary numeric;
BEGIN
	SELECT id,job FROM fstaff WHERE id=v_fs_id INTO v_id,v_job;
	IF coalesce(v_id,0)=0 THEN
		RAISE EXCEPTION 'There isnt flight staff with id % .',v_fs_id;
	END IF;
	-- check if emp is pilot or attendant
	select 1 from fspilots where emp_id=v_id INTO ispilot;
	select 1 from fsattendant where emp_id=v_id INTO isattendant;
	-- pairnw tis wres ptisis eswterikou kai ekswterikou gia kapoion iptameno
	select coalesce(sum(x.dom_dr),0) domestic_hr,coalesce(sum(x.int_dr),0) international_hr from 
	(select flight_hours(((arr_time)-(dep_time))::time)/60 dom_dr, 0.0 int_dr, * from staffschedule ss inner join flightdone fd on ss.fschedule_id=fd.fschedule_id 
	inner join get_flight_details gfd on ss.fschedule_id=gfd.fschedule_id 
	where emp_id=v_fs_id and (dep_country='Greece' and dest_country='Greece') and EXTRACT(MONTH FROM gfd.fdate)=v_month and EXTRACT(YEAR FROM gfd.fdate)=v_year
	union
	select 0.0 dom_dr, flight_hours(((arr_time)-(dep_time))::time)/60 int_dr, * from staffschedule ss inner join flightdone fd on ss.fschedule_id=fd.fschedule_id 
	inner join get_flight_details gfd on ss.fschedule_id=gfd.fschedule_id 
	where emp_id=v_fs_id and (dep_country<>'Greece' or dest_country<>'Greece') and EXTRACT(MONTH FROM gfd.fdate)=v_month and EXTRACT(YEAR FROM gfd.fdate)=v_year) x INTO v_domestic_hr,v_international_hr; 
	IF ispilot=1 THEN
		tot_salary=((v_domestic_hr*30)+(v_international_hr*60));
	ELSIF isattendant=1 THEN
		tot_salary=((v_domestic_hr*15)+(v_international_hr*30));
	END IF;
    LOOP
        -- first try to update the key
        UPDATE fsmonthlysalary SET dom_hours=v_domestic_hr, int_hours=v_international_hr, total=tot_salary WHERE fs_id=v_fs_id AND month=v_month AND year=v_year;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
            INSERT INTO fsmonthlysalary(fs_id,dom_hours,int_hours,total,month,year) VALUES (v_fs_id,v_domestic_hr,v_international_hr,tot_salary,v_month,v_year);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$;


ALTER FUNCTION public.update_fsmonthsalary(v_fs_id integer, v_month smallint, v_year smallint) OWNER TO postgres;

--
-- TOC entry 255 (class 1255 OID 159709)
-- Name: update_gstaff_transactions(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_gstaff_transactions(v_t_id integer, v_c_id integer, v_gstaff_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_action action;
	v_amount numeric;
	v_tran_date timestamp;
	is_ok integer;
	v_dep2 integer;
	v_dest2 integer;
	v_dep_country2 character varying;
	v_dest_country2 character varying;
	v_fschedule_id integer;
	v_dep_time timestamp;
BEGIN
	SELECT localtimestamp INTO v_tran_date;
        IF (coalesce((SELECT count(*) FROM transactions WHERE t_id=v_t_id),0))=0 THEN
                RAISE EXCEPTION 'Tranascation % doesnt exists.', v_t_id;
        END IF;
        IF (coalesce((SELECT count(*) FROM customer WHERE id=v_c_id),0))=0 THEN
                RAISE EXCEPTION 'Customer % doesnt exists.', v_c_id;
        END IF;        
        IF (coalesce((SELECT count(*) FROM gstaff WHERE id=v_gstaff_id),0))=0 THEN
                RAISE EXCEPTION 'Ground staff % doesnt exists.', v_tagent_id;
        END IF;
        IF (SELECT job FROM gstaff WHERE id=v_gstaff_id)='Engineer' THEN
		RAISE EXCEPTION 'Ground staff % isnt Employee.',v_gstaff_id;
        END IF;
        IF (coalesce((SELECT count(*) FROM waitinglist WHERE tid=v_t_id),0))<>0 THEN
                RAISE EXCEPTION 'Tranascation % exists in waitinglist.', v_t_id;
        END IF;
	-- pairnw ta stoixeia tis ptisis pou paw na eisagw gia agora eisitiriou
	SELECT tr.action, tr.price, tr.departure, tr.destination, tr.dep_country, tr.dest_country, tr.fschedule_id FROM get_trans_details tr INNER JOIN 	madetransaction mt on tr.t_id=mt.t_id WHERE tr.t_id=v_t_id AND tr.c_id=v_c_id AND mt.id=v_gstaff_id AND NOT EXISTS(SELECT tid FROM waitinglist WHERE tid=v_t_id) INTO v_action, v_amount, v_dep2, v_dest2, v_dep_country2, v_dest_country2, v_fschedule_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'The transaction doesnt meet the conditions of transaction id % or customer id % or staff id % .', v_t_id, v_c_id, v_gstaff_id;
	END IF;
	IF v_action<>'reserve' THEN
		RAISE EXCEPTION 'You can only buy reserved tickets.';
	END IF;

	SELECT fdate+dep_time FROM get_flight_details WHERE fschedule_id=v_fschedule_id INTO v_dep_time;
	-- den mporei na ginei agora kratimenou eisitiriou an perasoun 12 wres prin tin pragmatopoiisi tis ptisis
	IF v_tran_date>=(v_dep_time-'12:00'::interval) AND v_action='reserve' THEN 
		RAISE EXCEPTION 'You cant buy reserved ticket for flight % .',v_fschedule_id;
	END IF;
 
	-- pairnw ta dedomena tis kratisis pou exei kanei autos o pelatis tin idia mera
	SELECT 1 FROM get_trans_details WHERE c_id=v_c_id and action='buy' and departure=v_dest2 and destination=v_dep2 and (t_date::date)=(v_tran_date::date) ORDER BY t_date desc LIMIT 1 INTO is_ok; 
	-- an i imerominia agoras tou eisitiriou tis vasikis ptisis einai idia me auti tis epistrofis tote exoume ta eksis
	IF is_ok=1 THEN
		-- elegxoume an i ptisi epistrofis einai apo ekswteriko 'h eswteriko kai kanw tin antistoixi ekptwsi
		IF v_dep_country2<>'Greece' OR v_dest_country2<>'Greece' THEN
			v_amount=v_amount*0.85;
		ELSE
			v_amount=v_amount*0.92;
		END IF;
	END IF;
	UPDATE transactions SET action='buy', t_date=v_tran_date WHERE t_id=v_t_id AND c_id=v_c_id;  
	DELETE FROM reservation WHERE tid=v_t_id;
	INSERT INTO cashier(tid,amount) VALUES (v_t_id,v_amount); 
END;
$$;


ALTER FUNCTION public.update_gstaff_transactions(v_t_id integer, v_c_id integer, v_gstaff_id integer) OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 159710)
-- Name: update_tagent_transactions(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_tagent_transactions(v_t_id integer, v_c_id integer, v_tagent_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_action action;
	v_amount numeric;
	v_tran_date timestamp;
	is_ok integer;
	v_dep2 integer;
	v_dest2 integer;
	v_dep_country2 character varying;
	v_dest_country2 character varying;
	v_fschedule_id integer;
	v_dep_time timestamp;
BEGIN
        IF (coalesce((SELECT count(*) FROM transactions WHERE t_id=v_t_id),0))=0 THEN
                RAISE EXCEPTION 'Tranascation % doesnt exists.', v_t_id;
        END IF;
        IF (coalesce((SELECT count(*) FROM customer WHERE id=v_c_id),0))=0 THEN
                RAISE EXCEPTION 'Customer % doesnt exists.', v_c_id;
        END IF;        
        IF (coalesce((SELECT count(*) FROM travelagency WHERE id=v_tagent_id),0))=0 THEN
                RAISE EXCEPTION 'Agent % doesnt exists.', v_tagent_id;
        END IF;
        IF (coalesce((SELECT count(*) FROM waitinglist WHERE tid=v_t_id),0))<>0 THEN
                RAISE EXCEPTION 'Tranascation % exists in waitinglist.', v_t_id;
        END IF;
	SELECT localtimestamp INTO v_tran_date;
	-- pairnw ta stoixeia tis ptisis pou paw na eisagw gia agora eisitiriou
	SELECT tr.action, tr.price, tr.departure, tr.destination, tr.dep_country, tr.dest_country, tr.fschedule_id FROM get_trans_details tr INNER JOIN madetransaction mt on tr.t_id=mt.t_id 
	WHERE tr.t_id=v_t_id AND tr.c_id=v_c_id AND mt.id=v_tagent_id 
	AND NOT EXISTS(SELECT tid FROM waitinglist WHERE tid=v_t_id) INTO v_action, v_amount, v_dep2, v_dest2, v_dep_country2, v_dest_country2, v_fschedule_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'The transaction doesnt meet the conditions of transaction id % or customer id % or agent id % .', v_t_id, v_c_id, v_tagent_id;
	END IF;
	IF v_action<>'reserve' THEN
		RAISE EXCEPTION 'You can only buy reserved tickets.';
	END IF;
	
	SELECT fdate+dep_time FROM get_flight_details WHERE fschedule_id=v_fschedule_id INTO v_dep_time;
	-- den mporei na ginei agora kratimenou eisitiriou an perasoun 12 wres prin tin pragmatopoiisi tis ptisis
	IF v_tran_date>=(v_dep_time-'12:00'::interval) AND v_action='reserve' THEN 
		RAISE EXCEPTION 'You cant buy reserved ticket for flight % .',v_fschedule_id;
	END IF;
	
	-- pairnw ta dedomena tis kratisis pou exei kanei autos o pelatis tin idia mera
	SELECT 1 FROM get_trans_details WHERE c_id=v_c_id and action='buy' and departure=v_dest2 and destination=v_dep2 and (t_date::date)=(v_tran_date::date) ORDER BY t_date desc LIMIT 1 INTO is_ok;	
	-- an i imerominia agoras tou eisitiriou tis vasikis ptisis einai idia me auti tis epistrofis tote exoume ta eksis
	IF is_ok=1 THEN
		-- elegxoume an i ptisi epistrofis einai apo ekswteriko 'h eswteriko kai kanw tin antistoixi ekptwsi
		IF v_dep_country2<>'Greece' OR v_dest_country2<>'Greece' THEN
			v_amount=v_amount*0.85;
		ELSE
			v_amount=v_amount*0.92;
		END IF;
	END IF;
	UPDATE transactions SET action='buy', t_date=v_tran_date WHERE t_id=v_t_id AND c_id=v_c_id;
	-- UPDATE madetransaction SET id=v_tagent_id WHERE t_id=v_t_id AND type='tagent'; kai na vgaloume apo to where clause tou 2ou select to mt.id=v_tagent_id 
	DELETE FROM reservation WHERE tid=v_t_id;
	INSERT INTO cashier(tid,amount) VALUES (v_t_id,v_amount*0.988); 
END;
$$;


ALTER FUNCTION public.update_tagent_transactions(v_t_id integer, v_c_id integer, v_tagent_id integer) OWNER TO postgres;

--
-- TOC entry 257 (class 1255 OID 159711)
-- Name: updateflightschedule(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION updateflightschedule(fs_id integer, a_code integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_dep_city character varying;
	v_dr numeric;
	v_sc_hr numeric;
	v_t_hr numeric;
	v_cnt_hr numeric;
BEGIN
	-- Elegxw an to aeroskafos pou paw na valw yparxei.
	IF (SELECT count(*) FROM aircraft WHERE code=a_code)=0 THEN
		RAISE EXCEPTION 'There isnt an aircraft with code % .',a_code;
	END IF;
	-- Elegxw an o typos tou aeroskafous pou paw na valw einai idios me auton pou tha antikatastisw.
	IF a_code NOT IN (SELECT code FROM aircraft a INNER JOIN aircraft_type atp ON a.type_id=atp.id INNER JOIN flightsprogram fp ON atp.id=fp.aircraft_type INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id WHERE fs.fschedule_id=fs_id) THEN
		RAISE EXCEPTION 'Aircraft % is different type.',a_code;
	END IF;
	SELECT city FROM airport a INNER JOIN flight f ON a.code=f.departure INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code inner join flightschedule fs on fp.program_id=fs.fprogram_id WHERE fs.fschedule_id=fs_id INTO v_dep_city;
        IF v_dep_city<>'Athens' THEN
		RAISE EXCEPTION 'You must insert a basic flight.';
        END IF;
	-- pairnw tin diarkeia tis ptisis
	SELECT flight_hours(CAST(f.arr_time - f.dep_time AS time))/60 f_hours FROM flight f 
	INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
	INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
	WHERE fschedule_id=fs_id INTO v_dr;
	-- pairnw tis sinolikes wres pou exoun programmatistei
	SELECT coalesce(SUM(flight_hours(CAST(f.arr_time - f.dep_time AS time))/60),0) sch_hours FROM flight f 
	INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code
	INNER JOIN flightschedule fs ON fp.program_id=fs.fprogram_id
	WHERE NOT EXISTS (SELECT * FROM flightdone WHERE fschedule_id=fs.fschedule_id) AND fs.aircraft_code=a_code INTO v_sc_hr;
	-- pairnw tis sinolikes wres ptisis pou exoun pragmatopoihthei
	SELECT total_hours FROM aircraft WHERE code=a_code INTO v_t_hr;
	-- elegxw an tha kseperasei tis 150 wres
	v_cnt_hr=(v_t_hr+v_sc_hr);
	IF (((v_dr*2)+v_cnt_hr) > 150.0000000000000000) THEN
		RAISE EXCEPTION 'Aircraft % has reached the limit of 150 flight hours.Total hours % . Flight hours % .', a_code, round(v_cnt_hr,2), round((dr*2),2);
	END IF;
	-- Update ginetai stin vasiki ptisi ki tautoxrona omws allazei ki i ptisi epistrofis.
        -- Update stin vasiki ptisi.
	UPDATE flightschedule SET aircraft_code=a_code WHERE fschedule_id=fs_id;
	-- Update stin ptisi epistrofis.
	-- UPDATE flightschedule SET aircraft_code=a_code WHERE fschedule_id=fs_id+1;
	RETURN;
END;
$$;


ALTER FUNCTION public.updateflightschedule(fs_id integer, a_code integer) OWNER TO postgres;

--
-- TOC entry 201 (class 1255 OID 159712)
-- Name: updatestaffschedule(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION updatestaffschedule(fs_id integer, old_empid integer, new_empid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_dep_city character varying;
	old_ispilot smallint;
	new_ispilot smallint;
	old_isattendant smallint;
	new_isattendant smallint;
	sch_aircraft integer;
	exp_aircrafts integer[];
	dr numeric;
	sc_hr numeric;
	fl_date timestamp without time zone;
	fl_count integer;
	dp_time time;
	ar_time time;
BEGIN
	-- Elegxw an o employee pou paw na valw yparxei ston pinaka fstaff.
	IF (SELECT count(*) FROM fstaff WHERE id=new_empid)=0 THEN
		RAISE EXCEPTION 'There isnt flight staff employee with id % .',new_empid;
	END IF;
	-- Update ginetai stin vasiki ptisi ki tautoxrona omws allazei ki i ptisi epistrofis.
	SELECT city FROM airport a INNER JOIN flight f ON a.code=f.departure INNER JOIN flightsprogram fp ON f.fcode=fp.flight_code inner join flightschedule fs on fp.program_id=fs.fprogram_id WHERE fs.fschedule_id=fs_id INTO v_dep_city;
        IF v_dep_city<>'Athens' THEN
		RAISE EXCEPTION 'You must insert a basic flight.';
        END IF;
	-- Elegxw wste an o palios employee einai pilot prepei ki o kainourios na einai pilot.
	-- check if emp is pilot or attendant
	select 1 from fspilots where emp_id=old_empid INTO old_ispilot;
	--select 1 from fsattendant where emp_id=old_empid INTO old_isattendant;
	--pairnw tin imerominia kai wra tis ptisis opou vrisketai o palios ypallilos
	select fdate from staffschedule where emp_id=old_empid and fschedule_id=fs_id INTO fl_date;
	-- pairnw tis wra anaxwrisis kai afiksis tis ptisis
	select f.dep_time,f.arr_time from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	where fs.fschedule_id=fs_id INTO dp_time,ar_time; 
	-- pairnw tin diarkeia tis ptisis
	select flight_hours(cast(f.arr_time - f.dep_time as time))/60 f_hours from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	where fs.fschedule_id=fs_id INTO dr;
	-- get flight staff flight hours
	select coalesce(sum(flight_hours(cast(f.arr_time - f.dep_time as time)))/60,0) mytime from flight f inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where fs.fdate between (date_trunc('week', (fl_date)::timestamp)::date) and ((date_trunc('week', (fl_date)::timestamp)+ '6 days'::interval)::date) and ss.emp_id=new_empid INTO sc_hr;
	-- gia na elegksw an einai o ypallilos se alli ptisi tin idia mera ki wra
	select count(*) from flight f 
	inner join flightsprogram fp on f.fcode=fp.flight_code
	inner join flightschedule fs on fp.program_id=fs.fprogram_id
	inner join staffschedule ss on fs.fschedule_id=ss.fschedule_id
	where emp_id=new_empid and ss.fdate between (fl_date-'00:30'::interval) and (fl_date+((ar_time-dp_time)*2)+'01:00'::interval) INTO fl_count;
	
	IF old_ispilot=1 THEN
		select 1 from fspilots where emp_id=new_empid INTO new_ispilot;
		IF new_ispilot=1 THEN
			-- elegxoume an o pilotos pou vazoume mporei na petaksei auton ton typo aeroskafous pou tha ektelesei tin ptisi
			SELECT aircraft_type FROM get_flight_details WHERE fschedule_id=fs_id INTO sch_aircraft;
			SELECT array(SELECT aircraft_type FROM expertise WHERE emp_id=new_empid) INTO exp_aircrafts;
			IF sch_aircraft NOT IN (SELECT(unnest(exp_aircrafts))) THEN
				RAISE EXCEPTION 'Pilot % cannot fly aircraft type % .',new_empid, sch_aircraft;
			END IF;
			IF (fl_count>0) THEN
				RAISE EXCEPTION 'Pilot % is in another flight in the same hour and day.', new_empid;
			END IF;
			IF ((dr*2)+sc_hr > 25) THEN
				RAISE EXCEPTION 'Pilot % reached the limit of 25 weekly flight hours. Total hours % . Flight hours % .', new_empid, round(sc_hr,2), round((dr*2),2);
			END IF;
			UPDATE staffschedule SET emp_id=new_empid WHERE fschedule_id=fs_id AND emp_id=old_empid;
			-- UPDATE staffschedule SET emp_id=new_empid WHERE fschedule_id=fs_id+1 AND emp_id=old_empid;
		ELSE
			RAISE EXCEPTION 'Employee % isnt pilot.',new_empid;
		END IF;
	ELSE
		-- Elegxw wste an o palios employee einai attendant prepei ki o kainourios na einai attendant.
		select 1 from fsattendant where emp_id=new_empid INTO new_isattendant;
		IF new_isattendant=1 THEN
			IF (fl_count>0) THEN
				RAISE EXCEPTION 'Attendant % is in another flight in the same hour and day.', empid;
			END IF;
			IF ((dr*2)+sc_hr > 35) THEN
				RAISE EXCEPTION 'Attendant % reached the limit of 35 weekly flight hours. Total hours % . Flight hours % .', new_empid, round(sc_hr,2), round((dr*2),2);
			END IF;
			UPDATE staffschedule SET emp_id=new_empid WHERE fschedule_id=fs_id AND emp_id=old_empid;
			-- UPDATE staffschedule SET emp_id=new_empid WHERE fschedule_id=fs_id+1 AND emp_id=old_empid;
		ELSE
			RAISE EXCEPTION 'Employee % isnt attendant.',new_empid;
		END IF;
	END IF;
	RETURN;
END;
$$;


ALTER FUNCTION public.updatestaffschedule(fs_id integer, old_empid integer, new_empid integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 172 (class 1259 OID 159714)
-- Name: aircraft; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE aircraft (
    code integer NOT NULL,
    type_id integer NOT NULL,
    total_hours numeric NOT NULL,
    status smallint NOT NULL
);


ALTER TABLE aircraft OWNER TO postgres;

--
-- TOC entry 173 (class 1259 OID 159720)
-- Name: aircraft_type; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE aircraft_type (
    id integer NOT NULL,
    type character varying(45) NOT NULL,
    num_seats integer NOT NULL
);


ALTER TABLE aircraft_type OWNER TO postgres;

--
-- TOC entry 174 (class 1259 OID 159723)
-- Name: airport; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE airport (
    code integer NOT NULL,
    name character varying(45) NOT NULL,
    city character varying(45) NOT NULL,
    country character varying(45) NOT NULL,
    shortcut character varying(3) NOT NULL
);


ALTER TABLE airport OWNER TO postgres;

--
-- TOC entry 175 (class 1259 OID 159726)
-- Name: authoritytests; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE authoritytests (
    testcode integer NOT NULL,
    authorityname character varying(45) NOT NULL,
    pass_rank integer NOT NULL,
    description text
);


ALTER TABLE authoritytests OWNER TO postgres;

--
-- TOC entry 176 (class 1259 OID 159732)
-- Name: cashier; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE cashier (
    tid integer NOT NULL,
    amount numeric NOT NULL
);


ALTER TABLE cashier OWNER TO postgres;

--
-- TOC entry 177 (class 1259 OID 159738)
-- Name: customer; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE customer (
    id integer NOT NULL,
    fname character varying(45) NOT NULL,
    lname character varying(45) NOT NULL,
    age integer NOT NULL,
    sex sex,
    phone character varying(25) NOT NULL
);


ALTER TABLE customer OWNER TO postgres;

--
-- TOC entry 178 (class 1259 OID 159741)
-- Name: expertise; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE expertise (
    emp_id integer NOT NULL,
    aircraft_type integer NOT NULL
);


ALTER TABLE expertise OWNER TO postgres;

--
-- TOC entry 179 (class 1259 OID 159744)
-- Name: flight; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE flight (
    fcode integer NOT NULL,
    departure integer NOT NULL,
    destination integer NOT NULL,
    dep_time time without time zone NOT NULL,
    arr_time time without time zone NOT NULL,
    price numeric NOT NULL
);


ALTER TABLE flight OWNER TO postgres;

--
-- TOC entry 180 (class 1259 OID 159750)
-- Name: flight_days; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE flight_days (
    fcode integer NOT NULL,
    days days NOT NULL
);


ALTER TABLE flight_days OWNER TO postgres;

--
-- TOC entry 181 (class 1259 OID 159753)
-- Name: flightdone; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE flightdone (
    fschedule_id integer NOT NULL,
    duration time without time zone NOT NULL
);


ALTER TABLE flightdone OWNER TO postgres;

--
-- TOC entry 182 (class 1259 OID 159756)
-- Name: flightschedule; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE flightschedule (
    fschedule_id integer NOT NULL,
    aircraft_code integer NOT NULL,
    fdate date NOT NULL,
    fprogram_id integer NOT NULL
);


ALTER TABLE flightschedule OWNER TO postgres;

--
-- TOC entry 183 (class 1259 OID 159759)
-- Name: flightsprogram; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE flightsprogram (
    aircraft_type integer NOT NULL,
    flight_code integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    program_id integer NOT NULL
);


ALTER TABLE flightsprogram OWNER TO postgres;

--
-- TOC entry 184 (class 1259 OID 159762)
-- Name: fsattendant; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE fsattendant (
    emp_id integer NOT NULL,
    native_lang character varying(2) NOT NULL
);


ALTER TABLE fsattendant OWNER TO postgres;

--
-- TOC entry 185 (class 1259 OID 159765)
-- Name: fsmonthlysalary; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE fsmonthlysalary (
    fs_id integer NOT NULL,
    dom_hours numeric,
    int_hours numeric,
    total numeric,
    month smallint NOT NULL,
    year smallint NOT NULL
);


ALTER TABLE fsmonthlysalary OWNER TO postgres;

--
-- TOC entry 2284 (class 0 OID 0)
-- Dependencies: 185
-- Name: COLUMN fsmonthlysalary.dom_hours; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN fsmonthlysalary.dom_hours IS 'Domestic Flight Hours';


--
-- TOC entry 2285 (class 0 OID 0)
-- Dependencies: 185
-- Name: COLUMN fsmonthlysalary.int_hours; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN fsmonthlysalary.int_hours IS 'International Flight Hours';


--
-- TOC entry 2286 (class 0 OID 0)
-- Dependencies: 185
-- Name: COLUMN fsmonthlysalary.total; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN fsmonthlysalary.total IS 'Total Month Salary';


--
-- TOC entry 186 (class 1259 OID 159771)
-- Name: fspilots; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE fspilots (
    emp_id integer NOT NULL,
    degree character varying(45) NOT NULL,
    CONSTRAINT fspilots_degree_check CHECK (((degree)::text = ANY (ARRAY[('Commander'::character varying)::text, ('Copilot'::character varying)::text, ('Officer'::character varying)::text])))
);


ALTER TABLE fspilots OWNER TO postgres;

--
-- TOC entry 187 (class 1259 OID 159775)
-- Name: fstaff; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE fstaff (
    id integer NOT NULL,
    fname character varying(45) NOT NULL,
    lname character varying(45) NOT NULL,
    job character varying(45) NOT NULL,
    birthdate date NOT NULL,
    phone character varying(25) NOT NULL,
    address character varying(45)
);


ALTER TABLE fstaff OWNER TO postgres;

--
-- TOC entry 2287 (class 0 OID 0)
-- Dependencies: 187
-- Name: TABLE fstaff; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE fstaff IS 'Flight Staff (Pilots and Attendants)';


--
-- TOC entry 188 (class 1259 OID 159778)
-- Name: get_flight_details; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW get_flight_details AS
 SELECT x.fschedule_id,
    x.aircraft_code,
    x.fdate,
    x.fprogram_id,
    x.aircraft_type,
    x.flight_code,
    x.start_date,
    x.end_date,
    x.departure,
    x.destination,
    x.dep_time,
    x.arr_time,
    x.price,
    x.dep_city,
    x.dep_country,
    ar.city AS dest_city,
    ar.country AS dest_country,
    x.dep_shortcut AS dep_shrt,
    ar.shortcut AS dest_shrt
   FROM airport ar,
    ( SELECT fs.fschedule_id,
            fs.aircraft_code,
            fs.fdate,
            fs.fprogram_id,
            fp.aircraft_type,
            fp.flight_code,
            fp.start_date,
            fp.end_date,
            f.departure,
            f.destination,
            f.dep_time,
            f.arr_time,
            f.price,
            a.city AS dep_city,
            a.country AS dep_country,
            a.shortcut AS dep_shortcut
           FROM (((flightschedule fs
             JOIN flightsprogram fp ON ((fs.fprogram_id = fp.program_id)))
             JOIN flight f ON ((fp.flight_code = f.fcode)))
             JOIN airport a ON ((a.code = f.departure)))) x
  WHERE (ar.code = x.destination);


ALTER TABLE get_flight_details OWNER TO postgres;

--
-- TOC entry 189 (class 1259 OID 159783)
-- Name: transactions; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE transactions (
    t_id integer NOT NULL,
    fschedule_id integer NOT NULL,
    c_id integer NOT NULL,
    action action,
    t_date timestamp without time zone NOT NULL
);


ALTER TABLE transactions OWNER TO postgres;

--
-- TOC entry 190 (class 1259 OID 159786)
-- Name: get_trans_details; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW get_trans_details AS
 SELECT x.t_id,
    x.c_id,
    x.action,
    x.t_date,
    x.fschedule_id,
    x.aircraft_code,
    x.fdate,
    x.fprogram_id,
    x.aircraft_type,
    x.flight_code,
    x.start_date,
    x.end_date,
    x.departure,
    x.destination,
    x.dep_time,
    x.arr_time,
    x.price,
    x.dep_city,
    x.dep_country,
    ar.city AS dest_city,
    ar.country AS dest_country,
    x.dep_shortcut AS dep_shrt,
    ar.shortcut AS dest_shrt
   FROM airport ar,
    ( SELECT tr.t_id,
            tr.c_id,
            tr.action,
            tr.t_date,
            fs.fschedule_id,
            fs.aircraft_code,
            fs.fdate,
            fs.fprogram_id,
            fp.aircraft_type,
            fp.flight_code,
            fp.start_date,
            fp.end_date,
            f.departure,
            f.destination,
            f.dep_time,
            f.arr_time,
            f.price,
            a.city AS dep_city,
            a.country AS dep_country,
            a.shortcut AS dep_shortcut
           FROM ((((transactions tr
             JOIN flightschedule fs ON ((tr.fschedule_id = fs.fschedule_id)))
             JOIN flightsprogram fp ON ((fs.fprogram_id = fp.program_id)))
             JOIN flight f ON ((fp.flight_code = f.fcode)))
             JOIN airport a ON ((a.code = f.departure)))) x
  WHERE (ar.code = x.destination);


ALTER TABLE get_trans_details OWNER TO postgres;

--
-- TOC entry 191 (class 1259 OID 159791)
-- Name: gstaff; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE gstaff (
    id integer NOT NULL,
    fname character varying(45) NOT NULL,
    lname character varying(45) NOT NULL,
    job character varying(45),
    birthdate date NOT NULL,
    phone character varying(25) NOT NULL,
    address character varying(45),
    salary numeric
);


ALTER TABLE gstaff OWNER TO postgres;

--
-- TOC entry 2288 (class 0 OID 0)
-- Dependencies: 191
-- Name: TABLE gstaff; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE gstaff IS 'Ground Staff';


--
-- TOC entry 192 (class 1259 OID 159797)
-- Name: language; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE language (
    lang_code character varying(2) NOT NULL,
    name character varying(15) NOT NULL
);


ALTER TABLE language OWNER TO postgres;

--
-- TOC entry 193 (class 1259 OID 159800)
-- Name: madetransaction; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE madetransaction (
    id integer NOT NULL,
    t_id integer NOT NULL,
    type type NOT NULL
);


ALTER TABLE madetransaction OWNER TO postgres;

--
-- TOC entry 194 (class 1259 OID 159803)
-- Name: reservation; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE reservation (
    tid integer NOT NULL
);


ALTER TABLE reservation OWNER TO postgres;

--
-- TOC entry 195 (class 1259 OID 159806)
-- Name: services; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE services (
    emp_id integer NOT NULL,
    aircraft_id integer NOT NULL,
    service_date timestamp without time zone NOT NULL,
    rank integer NOT NULL,
    test_id integer NOT NULL,
    status smallint
);


ALTER TABLE services OWNER TO postgres;

--
-- TOC entry 196 (class 1259 OID 159809)
-- Name: spoken_langs; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE spoken_langs (
    emp_id integer NOT NULL,
    lang_code character varying(2) NOT NULL
);


ALTER TABLE spoken_langs OWNER TO postgres;

--
-- TOC entry 197 (class 1259 OID 159812)
-- Name: staffschedule; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE staffschedule (
    emp_id integer NOT NULL,
    fdate timestamp without time zone NOT NULL,
    fschedule_id integer NOT NULL
);


ALTER TABLE staffschedule OWNER TO postgres;

--
-- TOC entry 198 (class 1259 OID 159815)
-- Name: travelagency; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE travelagency (
    id integer NOT NULL,
    name character varying(45) NOT NULL,
    phone character varying(25) NOT NULL,
    address character varying(25) NOT NULL
);


ALTER TABLE travelagency OWNER TO postgres;

--
-- TOC entry 199 (class 1259 OID 159818)
-- Name: waitinglist; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE waitinglist (
    tid integer NOT NULL
);


ALTER TABLE waitinglist OWNER TO postgres;

--
-- TOC entry 2250 (class 0 OID 159714)
-- Dependencies: 172
-- Data for Name: aircraft; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (6, 3, 0, 1);
INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (3, 2, 0, 1);
INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (2, 1, 0, 1);
INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (5, 3, 0, 1);
INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (7, 2, 0, 1);
INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (4, 3, 0, 1);
INSERT INTO aircraft (code, type_id, total_hours, status) VALUES (1, 1, 0, 1);


--
-- TOC entry 2251 (class 0 OID 159720)
-- Dependencies: 173
-- Data for Name: aircraft_type; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO aircraft_type (id, type, num_seats) VALUES (1, 'Boeing747', 250);
INSERT INTO aircraft_type (id, type, num_seats) VALUES (2, 'AirBus300', 300);
INSERT INTO aircraft_type (id, type, num_seats) VALUES (3, 'Boeing737', 200);


--
-- TOC entry 2252 (class 0 OID 159723)
-- Dependencies: 174
-- Data for Name: airport; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO airport (code, name, city, country, shortcut) VALUES (2, 'Makedonia', 'Thessaloniki', 'Greece', 'SKG');
INSERT INTO airport (code, name, city, country, shortcut) VALUES (5, 'Heathrow', 'London', 'United Kingdom', 'LHR');
INSERT INTO airport (code, name, city, country, shortcut) VALUES (6, 'Charles de Gaulle', 'Paris', 'France', 'CDG');
INSERT INTO airport (code, name, city, country, shortcut) VALUES (1, 'Eleftherios Venizelos', 'Athens', 'Greece', 'ATH');
INSERT INTO airport (code, name, city, country, shortcut) VALUES (4, 'Ioannis Daskalogiannis', 'Chania', 'Greece', 'CHQ');
INSERT INTO airport (code, name, city, country, shortcut) VALUES (3, 'Nikos Kazantzakis', 'Heraklion', 'Greece', 'HER');


--
-- TOC entry 2253 (class 0 OID 159726)
-- Dependencies: 175
-- Data for Name: authoritytests; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO authoritytests (testcode, authorityname, pass_rank, description) VALUES (1, 'Test 1', 5, 'Sintirisi elikwn kai strovilwn');
INSERT INTO authoritytests (testcode, authorityname, pass_rank, description) VALUES (2, 'Test 2', 5, 'Sintirisi ilektrikwn sistimatwn');
INSERT INTO authoritytests (testcode, authorityname, pass_rank, description) VALUES (5, 'Test 5', 5, 'Sintirisi organwn kai ilektronikwn sistimatwn');
INSERT INTO authoritytests (testcode, authorityname, pass_rank, description) VALUES (4, 'Test 4', 5, 'Antidiavrwtikos elegxos');
INSERT INTO authoritytests (testcode, authorityname, pass_rank, description) VALUES (3, 'Test 3', 5, 'Sintirisi sistimatwn kausimou');


--
-- TOC entry 2254 (class 0 OID 159732)
-- Dependencies: 176
-- Data for Name: cashier; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO cashier (tid, amount) VALUES (1, 79.040);
INSERT INTO cashier (tid, amount) VALUES (2, 79.040);
INSERT INTO cashier (tid, amount) VALUES (3, 79.040);
INSERT INTO cashier (tid, amount) VALUES (4, 79.040);
INSERT INTO cashier (tid, amount) VALUES (5, 79.040);
INSERT INTO cashier (tid, amount) VALUES (16, 79.040);
INSERT INTO cashier (tid, amount) VALUES (17, 79.040);
INSERT INTO cashier (tid, amount) VALUES (18, 79.040);
INSERT INTO cashier (tid, amount) VALUES (19, 79.040);
INSERT INTO cashier (tid, amount) VALUES (20, 79.040);
INSERT INTO cashier (tid, amount) VALUES (31, 79.040);
INSERT INTO cashier (tid, amount) VALUES (32, 79.040);
INSERT INTO cashier (tid, amount) VALUES (33, 79.040);
INSERT INTO cashier (tid, amount) VALUES (34, 79.040);
INSERT INTO cashier (tid, amount) VALUES (35, 79.040);
INSERT INTO cashier (tid, amount) VALUES (46, 79.040);
INSERT INTO cashier (tid, amount) VALUES (47, 79.040);
INSERT INTO cashier (tid, amount) VALUES (48, 79.040);
INSERT INTO cashier (tid, amount) VALUES (49, 79.040);
INSERT INTO cashier (tid, amount) VALUES (50, 79.040);
INSERT INTO cashier (tid, amount) VALUES (61, 79.040);
INSERT INTO cashier (tid, amount) VALUES (62, 79.040);
INSERT INTO cashier (tid, amount) VALUES (63, 79.040);
INSERT INTO cashier (tid, amount) VALUES (64, 79.040);
INSERT INTO cashier (tid, amount) VALUES (65, 79.040);
INSERT INTO cashier (tid, amount) VALUES (76, 79.040);
INSERT INTO cashier (tid, amount) VALUES (77, 79.040);
INSERT INTO cashier (tid, amount) VALUES (78, 79.040);
INSERT INTO cashier (tid, amount) VALUES (79, 79.040);
INSERT INTO cashier (tid, amount) VALUES (80, 79.040);
INSERT INTO cashier (tid, amount) VALUES (91, 79.040);
INSERT INTO cashier (tid, amount) VALUES (92, 79.040);
INSERT INTO cashier (tid, amount) VALUES (93, 79.040);
INSERT INTO cashier (tid, amount) VALUES (94, 79.040);
INSERT INTO cashier (tid, amount) VALUES (95, 79.040);
INSERT INTO cashier (tid, amount) VALUES (106, 79.040);
INSERT INTO cashier (tid, amount) VALUES (107, 79.040);
INSERT INTO cashier (tid, amount) VALUES (108, 79.040);
INSERT INTO cashier (tid, amount) VALUES (109, 79.040);
INSERT INTO cashier (tid, amount) VALUES (110, 79.040);
INSERT INTO cashier (tid, amount) VALUES (6, 79.040);
INSERT INTO cashier (tid, amount) VALUES (7, 79.040);
INSERT INTO cashier (tid, amount) VALUES (36, 79.040);
INSERT INTO cashier (tid, amount) VALUES (37, 79.040);
INSERT INTO cashier (tid, amount) VALUES (38, 79.040);
INSERT INTO cashier (tid, amount) VALUES (111, 79.040);
INSERT INTO cashier (tid, amount) VALUES (112, 79.040);
INSERT INTO cashier (tid, amount) VALUES (113, 79.040);
INSERT INTO cashier (tid, amount) VALUES (114, 79.040);
INSERT INTO cashier (tid, amount) VALUES (123, 80);
INSERT INTO cashier (tid, amount) VALUES (124, 80);
INSERT INTO cashier (tid, amount) VALUES (125, 80);
INSERT INTO cashier (tid, amount) VALUES (126, 80);
INSERT INTO cashier (tid, amount) VALUES (134, 79.040);


--
-- TOC entry 2255 (class 0 OID 159738)
-- Dependencies: 177
-- Data for Name: customer; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (1, 'Giannis', 'Morras', 18, 'M', '2310111222');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (2, 'Konstantinos', 'Xortareas', 25, 'M', '2310111333');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (3, 'Dimitris', 'Mitsopoulos', 31, 'M', '2310111444');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (4, 'Athanasios', 'Papadopoulos', 45, 'M', '2310111555');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (5, 'Nick', 'Stamatopoulos', 32, 'M', '2310111666');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (6, 'Evaggelia', 'Kiriakou', 49, 'F', '2310111777');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (7, 'Maria', 'Antonopoulou', 58, 'F', '2310111888');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (8, 'Nikiforos', 'Vamvoukas', 65, 'M', '2310111999');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (9, 'Walter', 'Brien', 27, 'M', '2310222000');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (10, 'Katie', 'Cassidy', 29, 'F', '2310222111');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (11, 'David', 'Ramsey', 33, 'M', '2310222333');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (12, 'Willa', 'Holland', 24, 'F', '2310222444');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (13, 'Grant', 'Gustin', 25, 'M', '2310222555');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (14, 'Candice', 'Patton', 25, 'F', '2310222666');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (15, 'Ben', 'McKenzie', 33, 'M', '2310222777');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (16, 'Erin', 'Richards', 31, 'F', '2310222888');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (17, 'Clark', 'Gregg', 40, 'M', '2310222999');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (18, 'Elizabeth', 'Henstridge', 24, 'F', '2310333000');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (19, 'Cloe', 'Bennet', 26, 'F', '2310333111');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (20, 'Brett', 'Dalton', 28, 'M', '2310333222');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (21, 'Oliver', 'Queen', 25, 'M', '1111111111');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (22, 'Laurel', 'Lance', 23, 'F', '2222222222');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (23, 'John', 'Diggle', 28, 'M', '3333333333');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (24, 'Thea', 'Queen', 21, 'F', '4444444444');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (25, 'Quentin', 'Lance', 48, 'M', '5555555555');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (26, 'Felicity', 'Smoak', 24, 'F', '6666666666');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (27, 'Roy', 'Harper', 24, 'M', '7777777777');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (28, 'Moira', 'Queen', 46, 'F', '8888888888');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (29, 'Malcolm', 'Merlyn', 48, 'M', '9999999999');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (30, 'Slade', 'Wilson', 35, 'M', '1010101010');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (31, 'Bary', 'Allen', 26, 'M', '2020202020');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (32, 'Iris', 'West', 24, 'F', '3030303030');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (33, 'Caitlin', 'Snow', 26, 'F', '4040404040');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (34, 'Eddie', 'Thaune', 27, 'M', '5050505050');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (35, 'Cisco', 'Ramon', 25, 'M', '6060606060');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (36, 'Harrison', 'Wells', 40, 'M', '7070707070');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (37, 'Joe', 'West', 44, 'M', '8080808080');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (38, 'Tyrion', 'Lannister', 38, 'M', '9090909090');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (39, 'Cersei', 'Lannister', 34, 'F', '1234567890');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (40, 'Jon', 'Snow', 28, 'M', '1234567891');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (41, 'Arya', 'Stark', 14, 'F', '1234567892');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (42, 'Sansa', 'Stark', 14, 'F', '1234567893');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (43, 'James', 'Gordon', 31, 'M', '1234567894');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (44, 'Harvey', 'Bullock', 38, 'M', '1234567895');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (45, 'Bruce', 'Wayne', 15, 'M', '1234567896');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (46, 'Sarah', 'Essen', 17, 'F', '1234567897');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (47, 'Barbara', 'Kean', 27, 'F', '1234567898');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (48, 'Phil', 'Coulson', 36, 'M', '1234567899');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (49, 'Melinda', 'May', 34, 'F', '2310000000');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (50, 'Leo', 'Fitz', 24, 'M', '2310000001');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (51, 'Jemma', 'Simmons', 24, 'F', '2310000002');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (52, 'Grant', 'Ward', 28, 'M', '2310000003');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (53, 'John', 'Reese', 35, 'M', '2310000004');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (54, 'Lionel', 'Fusco', 45, 'M', '2310000005');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (55, 'Harold', 'Finch', 45, 'M', '2310000006');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (56, 'Joss', 'Carter', 45, 'F', '2310000007');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (57, 'Sameen', 'Shaw', 35, 'F', '2310000008');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (58, 'Walter', 'McBrien', 27, 'M', '2310000009');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (59, 'Paige', 'Dineen', 29, 'F', '2310000010');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (60, 'Toby', 'Curtis', 30, 'M', '2310000011');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (61, 'Happy', 'Quinn', 28, 'F', '2310000012');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (62, 'Sylvester', 'Dodd', 26, 'M', '2310000013');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (63, 'Cabe', 'Gallo', 48, 'M', '2310000014');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (64, 'Ralph', 'Dineen', 14, 'M', '2310000015');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (65, 'Ragnar', 'Lothbrok', 36, 'M', '2310000016');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (66, 'Rollo', 'Lothbrok', 34, 'M', '2310000017');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (67, 'Siggy', 'Haraldson', 31, 'F', '2310000018');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (68, 'Sofi', 'Lila', 58, 'F', '2310000019');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (69, 'Simos', 'Tsapnidis', 54, 'M', '2310000020');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (70, 'Lefteris', 'Kastritsios', 68, 'M', '2310000021');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (71, 'Maria', 'Marsellou', 59, 'F', '2310000022');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (72, 'Fani', 'Nikolaidou', 78, 'F', '2310000023');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (73, 'Stefanos', 'Fotiadis', 65, 'M', '2310000024');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (74, 'Giannis', 'Nikolaidis', 51, 'M', '2310000025');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (75, 'Giannis', 'Dalianidis', 74, 'M', '2310000026');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (76, 'Mitsos', 'Paulatos', 41, 'M', '2310000027');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (77, 'Melita', 'Michail', 50, 'F', '2310000028');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (78, 'Frantzeska', 'Salieri', 25, 'F', '2310000029');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (79, 'Roksani', 'Ntanou', 32, 'F', '2310000030');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (80, 'Foteini', 'Mpartzoka', 40, 'F', '2310000031');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (81, 'Paulina', 'Kakoudaki', 41, 'F', '2310000032');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (82, 'Maria', 'Skarmoutsou', 21, 'F', '2310000033');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (83, 'Xronis', 'Mpatsinilas', 51, 'M', '2310000034');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (84, 'Hulia', 'Osman', 32, 'F', '2310000035');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (85, 'Stella', 'Priovolou', 36, 'F', '2310000036');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (86, 'Kanellos', 'Katsifaras', 46, 'M', '2310000037');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (87, 'Maria', 'Kalafaki', 52, 'F', '2310000038');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (88, 'Persa', 'Aivalioti', 55, 'F', '2310000039');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (89, 'Kaiti', 'Terzidi', 42, 'F', '2310000040');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (90, 'Foteini', 'Lampropoulou', 32, 'F', '2310000041');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (91, 'Giagkos', 'Drakos', 55, 'M', '2310000042');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (92, 'Virna', 'Drakou', 51, 'F', '2310000043');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (93, 'Aleksis', 'Drakos', 35, 'M', '2310000044');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (94, 'Renos', 'Velmiras', 38, 'M', '2310000045');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (95, 'Dionisis', 'Dagkas', 40, 'M', '2310000046');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (96, 'Vasiliki', 'Asproleonta', 36, 'F', '2310000047');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (97, 'Timotheos', 'Stamatis', 40, 'M', '2310000048');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (98, 'Athina', 'Kouroupa', 38, 'F', '2310000049');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (99, 'Leonidas', 'Archos', 60, 'M', '2310000050');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (100, 'Antigoni', 'Archou', 54, 'F', '2310000051');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (101, 'Ksenia', 'Archou', 27, 'F', '2310000053');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (102, 'Stathis', 'Theocharis', 55, 'M', '2310000054');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (103, 'Dimitris', 'Aronis', 50, 'M', '2310000055');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (104, 'Eulogitos', 'Kakos', 35, 'M', '2310000056');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (105, 'Parthena', 'Oustampasidou', 50, 'F', '2310000057');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (106, 'Natas', 'Saritzoglou', 40, 'F', '2310000058');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (107, 'Antonia', 'Lazaridou', 35, 'F', '2310000059');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (108, 'Vasilis', 'Papadopoulos', 30, 'M', '2310000060');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (109, 'Smaragda', 'Lazaridou', 28, 'F', '2310000061');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (110, 'Maria', 'Theofanous', 35, 'F', '2310000062');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (111, 'Stelios', 'Damigos', 38, 'M', '2310000063');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (112, 'Makis', 'Toufeksis', 35, 'M', '2310000064');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (113, 'Champos', 'Oustampasidis', 45, 'M', '2310000065');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (114, 'Antonis', 'Tzoumanikas', 48, 'M', '2310000066');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (115, 'Konstantinos', 'Katakouzinos', 45, 'M', '2310000067');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (116, 'Eleni', 'Vlachaki', 35, 'F', '2310000068');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (117, 'Manthos', 'Foustanos', 38, 'M', '2310000069');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (118, 'Pegki', 'Karra', 34, 'F', '2310000070');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (119, 'Matina', 'Mantarinaki', 36, 'F', '2310000071');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (120, 'Flora', 'Mousoutsani', 34, 'F', '2310000072');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (121, 'Alekos', 'Papadimas', 38, 'M', '2310000073');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (122, 'Axilleas', 'Mitropoulos', 37, 'M', '2310000074');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (123, 'Soso', 'Papadima', 36, 'F', '2310000075');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (124, 'Korina', 'Koutsoumpa', 33, 'F', '2310000076');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (125, 'Maxi', 'Karathanou', 66, 'F', '2310000077');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (126, 'Michalakis', 'Roupakas', 27, 'M', '2310000078');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (127, 'Aleksandros', 'Theotokatos', 45, 'M', '2310000079');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (128, 'Margarita', 'Petridou', 42, 'F', '2310000080');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (129, 'Tzoulia', 'Xourmouziadou', 70, 'F', '2310000081');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (130, 'Hlias', 'Chatzidimitrakopoulos', 42, 'M', '2310000082');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (131, 'Chara', 'Petridou', 37, 'F', '2310000083');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (132, 'Nikos', 'Mpezentakos', 37, 'M', '2310000084');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (133, 'Viki', 'Seitanidi', 34, 'F', '2310000085');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (134, 'Grigoris', 'Kapernaros', 35, 'M', '2310000086');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (135, 'Stella', 'Papalimnaiou', 32, 'F', '2310000087');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (136, 'Lazaros', 'Karageorgopoulos', 29, 'M', '2310000088');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (137, 'Periandros', 'Popotas', 45, 'M', '2310000089');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (138, 'Chara', 'Chaska', 42, 'F', '2310000090');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (139, 'Vaggelis', 'Fatseas', 38, 'M', '2310000091');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (140, 'Nikiforos', 'Zormpas', 48, 'M', '2310000092');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (141, 'Mimis', 'Sarantinos', 47, 'M', '2310000093');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (142, 'Paulos', 'Strateas', 46, 'M', '2310000094');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (143, 'Elisavet', 'Dimaki', 42, 'F', '2310000095');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (144, 'Ksanthipi', 'Alevizou', 42, 'F', '2310000096');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (145, 'Eirini', 'Karampeti', 42, 'F', '2310000097');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (146, 'Maria', 'Papadopoulou', 35, 'F', '2310000098');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (147, 'Alkis', 'Mpeloutsis', 55, 'M', '2310000099');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (148, 'Ntalia', 'Chatzialeksandrou', 35, 'F', '2310000100');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (149, 'Zoumpoulia', 'Ampatzidou', 52, 'F', '2310000101');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (150, 'Spiros', 'Deloglou', 27, 'M', '2310000102');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (151, 'Fotis', 'Voulinos', 29, 'M', '2310000103');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (152, 'Aggela', 'Ioakeimidou', 24, 'F', '2310000104');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (153, 'Dionisis', 'Maurotsoukalos', 55, 'M', '2310000105');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (154, 'Eleni', 'Palaiologlou', 48, 'F', '2310000106');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (155, 'Spiros', 'Maurotsoukalos', 57, 'M', '2310000107');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (156, 'Markos', 'Maurotsoukalos', 17, 'M', '2310000108');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (157, 'Thanasis', 'Maurotsoukalos', 15, 'M', '2310000109');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (158, 'Giannakis', 'Maurotsoukalos', 10, 'M', '2310000110');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (159, 'Makis', 'Kotsampasis', 50, 'M', '2310000111');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (160, 'Makis', 'Dimakis', 37, 'M', '2310000112');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (161, 'Kostas', 'Mpakaftias', 23, 'M', '123456789');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (162, 'Vassilis', 'Peftoxeilis', 24, 'M', '987654321');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (163, 'Giannis', 'Maregkas', 25, 'M', '000111222');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (164, 'Kosmas', 'Trypokoilis', 26, 'M', '333444555');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (165, 'Axilleas', 'Ogunsoto', 27, 'M', '666777888999');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (166, 'Antonis', 'Pertesis', 28, 'M', '121314151');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (167, 'Sakis', 'Alefantos', 29, 'M', '213141516');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (168, 'Manwlis', 'Athanasiadis', 30, 'M', '102030405');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (169, 'Maria', 'Kontostoupa', 31, 'F', '100200300');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (170, 'Eleni', 'Xontrompala', 31, 'F', '400500600');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (171, 'Eirini', 'Trixwth', 10, 'F', '919293949');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (172, 'Iwanna', 'Kotokoilitsa', 11, 'F', '818283848');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (173, 'Xristina', 'Alepoudooura', 12, 'F', '717273747');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (174, 'Despoina', 'Mantalena', 13, 'F', '616263646');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (175, 'Giota', 'Pontikomamh', 14, 'F', '515253545');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (176, 'Eleeini', 'Stoupa', 15, 'F', '414243444');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (177, 'Artemis', 'Diplontoulapa', 16, 'F', '313233343');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (178, 'Krystallia', 'Partheniou', 17, 'F', '112233445');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (179, 'Sofoklis', 'Stratopaliouras', 18, 'M', '111222333');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (180, 'Xristodoulos', 'Mamouths', 18, 'M', '111122223');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (181, 'Dias', 'Monokeros', 90, 'M', '000000000');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (182, 'Poseidwnas', 'Triainas', 91, 'M', '111111111');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (183, 'Adhs', 'Diavolos', 92, 'M', '222222222');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (184, 'Arhs', 'Strathgos', 93, 'M', '333333333');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (185, 'Hfaistos', 'Mastori', 95, 'M', '555555555');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (186, 'Ermhs', 'Fterwtos', 94, 'M', '444444444');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (187, 'Hra', 'Ierodouli', 96, 'F', '666666666');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (188, 'Afroditi', 'Omorfi', 97, 'F', '112233445');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (189, 'Dimitra', 'Gewrgos', 98, 'F', '111222333');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (190, 'Apollwnas', 'Lamperos', 99, 'M', '111122223');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (191, 'Millhouse', 'Manastorm', 40, 'M', '210000123');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (192, 'Lorewalker', 'Cho', 25, 'M', '210000456');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (193, 'Nat', 'Paggle', 31, 'M', '210000789');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (194, 'Bloodmage', 'Thalnos', 50, 'M', '210000321');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (195, 'Ragnaros', 'Firelord', 60, 'M', '210000654');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (196, 'Alakir', 'Windlord', 62, 'M', '210000987');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (197, 'Deathwing', 'Dragon', 70, 'M', '210000963');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (198, 'Alexstraasza', 'Dragon', 71, 'M', '210000852');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (199, 'Thadius', 'Feugeun', 55, 'M', '210000741');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (200, 'Thadius', 'Stalagg', 55, 'M', '210000753');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (201, 'Mukla', 'King', 50, 'M', '210000357');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (202, 'Krush', 'King', 51, 'M', '210000123135');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (203, 'Lord', 'Jarraxus', 52, 'M', '210000680');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (204, 'Majordomus', 'Executor', 53, 'M', '210000246');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (205, 'Onyxia', 'Dragon', 54, 'M', '210000802');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (206, 'Malganis', 'Demon', 55, 'M', '210000159');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (207, 'Malygos', 'Dragon', 56, 'M', '210000951');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (208, 'Nozdormu', 'Dragon', 57, 'M', '210000842');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (209, 'Ysera', 'Dragon', 58, 'M', '210000268');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (210, 'Gromass', 'Hellscream', 59, 'M', '210000346');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (211, 'Tirion', 'Fordring', 40, 'M', '210000312');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (212, 'Archmage', 'Antonidas', 41, 'M', '210000123198');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (213, 'Baron', 'Geddon', 42, 'M', '210000656');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (214, 'Doctor', 'Boom', 43, 'M', '210000231');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (215, 'Flame', 'Leviathan', 44, 'M', '210000845');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (216, 'Gahz', 'Rilla', 45, 'M', '210000175');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (217, 'Malorne', 'Horse', 46, 'F', '210000965');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (218, 'Neptulon', 'Murloc', 47, 'F', '210000839');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (219, 'Prophet', 'Velen', 48, 'F', '210000243');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (220, 'Rend', 'Blackhand', 49, 'M', '210000326');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (221, 'Troggzor', 'Earthinator', 30, 'M', '210000311');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (222, 'Cairne', 'Bloddhoof', 31, 'M', '210000123112');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (223, 'Emperor', 'Thaurissan', 32, 'M', '210000613');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (224, 'Gazlowe', 'Troll', 33, 'M', '210000214');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (225, 'Gebbin', 'Mekkatorque', 34, 'M', '210000815');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (226, 'Hogger', 'Wolf', 35, 'F', '210000116');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (227, 'Illidan', 'Stromrage', 36, 'M', '210000917');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (228, 'Iron', 'Juggernaut', 37, 'M', '210000818');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (229, 'Maexxna', 'Spider', 38, 'F', '210000219');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (230, 'Mogor', 'Ogre', 39, 'M', '210000320');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (231, 'Sylvanas', 'Wildrunner', 80, 'M', '210000321');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (232, 'The', 'Beast', 81, 'M', '210000123122');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (233, 'Black', 'Knight', 82, 'F', '210000623');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (234, 'Toshley', 'Killer', 83, 'M', '210000224');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (235, 'Trade Prince', 'Gallywix', 84, 'F', '210000825');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (236, 'Blingtron', 'Robot', 85, 'M', '210000126');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (237, 'Bolvar', 'Fordragon', 86, 'F', '210000927');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (238, 'Captain', 'Greenskin', 87, 'M', '210000828');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (239, 'Elite Tauren', 'Chieftain', 88, 'F', '210000229');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (240, 'Feugen', 'Monster', 89, 'M', '210000330');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (241, 'Stalagg', 'Monster', 20, 'M', '210000331');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (242, 'Harrison', 'Jones', 21, 'F', '210000123132');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (243, 'Hemet', 'Nesingway', 22, 'M', '210000633');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (244, 'Leeroy', 'Jenkins', 23, 'F', '210000234');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (245, 'Loatheb', 'Dead', 24, 'M', '210000835');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (246, 'Magmatron', 'Firecontroller', 25, 'F', '210000136');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (247, 'Magmaw', 'Firecontroller', 26, 'M', '210000937');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (248, 'Mimitron', 'Head', 27, 'F', '210000838');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (249, 'Vol', 'Jiin', 28, 'M', '210000239');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (250, 'Baine', 'Bloodhoof', 29, 'F', '210000340');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (251, 'Baron', 'Rivendare', 30, 'M', '210000341');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (252, 'Old', 'MurkEye', 31, 'F', '210000123142');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (253, 'Edwin', 'VanCleef', 32, 'M', '210000643');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (254, 'Electron', 'Electricity', 33, 'F', '210000244');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (255, 'Tinkmaster', 'Overspark', 34, 'M', '210000845');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (256, 'Finkle', 'Einhorn', 35, 'F', '210000146');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (257, 'Mister', 'Bigglesworth', 36, 'M', '210000947');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (258, 'Toxitron', 'Toxic', 37, 'F', '210000848');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (259, 'Arcanotron', 'Arcane', 38, 'M', '210000249');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (260, 'Faceless', 'Manipulator', 39, 'F', '210000350');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (261, 'Iker', 'Cassilas', 33, 'M', '123456751');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (262, 'Sergio', 'Ramos', 32, 'M', '987654352');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (263, 'Rafael', 'Varane', 25, 'M', '000111253');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (264, 'Keylor', 'Navas', 29, 'M', '333444554');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (265, 'Fabio', 'Coentrao', 30, 'M', '666777888955');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (266, 'Lucas', 'Silva', 26, 'M', '121314156');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (267, 'James', 'Rodriguez', 28, 'M', '213141557');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (268, 'Gareth', 'Bale', 30, 'M', '102030458');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (269, 'Luca', 'Modric', 27, 'M', '100200359');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (270, 'Cristiano', 'Ronaldo', 30, 'M', '400500060');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (271, 'Marc', 'TerStegn', 33, 'M', '123456761');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (272, 'Gerard', 'Pique', 32, 'M', '987654362');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (273, 'Ivan', 'Rakitic', 25, 'M', '000111263');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (274, 'Xavi', 'Hernadez', 29, 'M', '333444564');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (275, 'Pedro', 'Rodriguez', 30, 'M', '666777888965');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (276, 'Andres', 'Iniesta', 26, 'M', '121314166');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (277, 'Lionel', 'Messi', 28, 'M', '213141567');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (278, 'Neymar', 'Da Silva', 30, 'M', '102030468');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (279, 'Luis', 'Suarez', 27, 'M', '100200369');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (280, 'Daniel', 'Silva', 30, 'M', '400500070');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (281, 'Thomas', 'Muller', 33, 'M', '123456761');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (282, 'Pepe', 'Reina', 32, 'M', '987654362');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (283, 'Jerome', 'Boateng', 25, 'M', '000111263');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (284, 'Philip', 'Lahm', 29, 'M', '333444564');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (285, 'David', 'Alaba', 30, 'M', '666777888965');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (286, 'Xabi', 'Alonso', 26, 'M', '121314166');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (287, 'Frank', 'Ribery', 28, 'M', '213141567');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (288, 'Arjen', 'Robben', 30, 'M', '102030468');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (289, 'Mario', 'Gotse', 27, 'M', '100200369');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (290, 'Bastian', 'Schewinsteiger', 30, 'M', '400500070');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (291, 'Natcho', 'Scocco', 33, 'M', '12345671');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (292, 'Ismael', 'Blanco', 32, 'M', '987654372');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (293, 'Xristos', 'Aravidis', 25, 'M', '000111273');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (294, 'Nikos', 'Lymperopoulos', 29, 'M', '333444574');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (295, 'Petros', 'Mantalos', 30, 'M', '666777888975');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (296, 'Julio', 'Cesar', 26, 'M', '121314176');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (297, 'Vitor', 'Rivaldo', 28, 'M', '213141577');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (298, 'Pantelis', 'Kafes', 30, 'M', '102030478');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (299, 'Ntemis', 'Nikolaidis', 27, 'M', '100200379');
INSERT INTO customer (id, fname, lname, age, sex, phone) VALUES (300, 'Gustavo', 'Manduca', 30, 'M', '400500080');


--
-- TOC entry 2256 (class 0 OID 159741)
-- Dependencies: 178
-- Data for Name: expertise; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO expertise (emp_id, aircraft_type) VALUES (1, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (1, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (1, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (2, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (2, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (2, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (3, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (3, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (3, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (4, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (4, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (4, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (5, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (5, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (5, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (6, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (6, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (6, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (7, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (7, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (7, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (8, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (8, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (8, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (9, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (9, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (9, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (10, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (10, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (10, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (11, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (11, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (11, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (12, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (12, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (12, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (13, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (13, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (13, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (14, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (14, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (14, 3);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (15, 1);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (15, 2);
INSERT INTO expertise (emp_id, aircraft_type) VALUES (15, 3);


--
-- TOC entry 2257 (class 0 OID 159744)
-- Dependencies: 179
-- Data for Name: flight; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (1, 1, 2, '07:00:00', '08:00:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (2, 2, 1, '08:30:00', '09:30:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (3, 1, 2, '13:00:00', '14:00:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (4, 2, 1, '14:30:00', '15:30:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (5, 1, 2, '19:00:00', '20:00:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (6, 2, 1, '20:30:00', '21:30:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (9, 1, 3, '18:00:00', '18:50:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (7, 1, 3, '07:00:00', '07:50:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (11, 1, 4, '08:15:00', '08:55:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (12, 4, 1, '09:25:00', '10:05:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (13, 1, 4, '15:00:00', '15:40:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (14, 4, 1, '16:10:00', '16:50:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (15, 1, 5, '10:30:00', '13:00:00', 120);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (16, 5, 1, '13:30:00', '16:00:00', 120);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (17, 1, 5, '20:30:00', '23:00:00', 120);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (18, 5, 1, '23:30:00', '02:00:00', 120);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (19, 1, 6, '10:30:00', '13:30:00', 120);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (20, 6, 1, '14:00:00', '17:00:00', 120);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (8, 3, 1, '08:20:00', '09:10:00', 80);
INSERT INTO flight (fcode, departure, destination, dep_time, arr_time, price) VALUES (10, 3, 1, '19:20:00', '20:10:00', 80);


--
-- TOC entry 2258 (class 0 OID 159750)
-- Dependencies: 180
-- Data for Name: flight_days; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO flight_days (fcode, days) VALUES (1, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (1, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (1, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (1, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (1, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (2, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (2, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (2, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (2, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (2, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (3, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (3, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (3, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (3, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (3, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (4, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (4, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (4, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (4, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (4, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (5, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (5, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (5, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (5, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (5, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (6, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (6, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (6, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (6, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (6, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (7, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (7, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (7, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (7, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (7, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (8, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (8, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (8, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (8, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (8, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (9, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (9, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (9, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (9, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (9, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (10, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (10, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (10, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (10, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (10, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (11, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (11, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (11, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (11, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (11, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (12, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (12, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (12, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (12, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (12, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (13, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (13, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (13, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (13, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (13, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (14, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (14, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (14, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (14, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (14, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (15, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (15, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (15, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (15, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (15, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (16, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (16, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (16, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (16, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (16, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (17, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (17, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (17, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (17, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (17, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (18, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (18, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (18, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (18, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (18, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (19, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (19, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (19, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (19, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (19, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (20, 'MON');
INSERT INTO flight_days (fcode, days) VALUES (20, 'TUE');
INSERT INTO flight_days (fcode, days) VALUES (20, 'WED');
INSERT INTO flight_days (fcode, days) VALUES (20, 'THU');
INSERT INTO flight_days (fcode, days) VALUES (20, 'FRI');
INSERT INTO flight_days (fcode, days) VALUES (7, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (8, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (15, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (16, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (19, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (20, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (17, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (18, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (19, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (20, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (1, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (2, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (3, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (4, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (9, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (10, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (11, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (12, 'SAT');
INSERT INTO flight_days (fcode, days) VALUES (13, 'SUN');
INSERT INTO flight_days (fcode, days) VALUES (14, 'SUN');


--
-- TOC entry 2259 (class 0 OID 159753)
-- Dependencies: 181
-- Data for Name: flightdone; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 2260 (class 0 OID 159756)
-- Dependencies: 182
-- Data for Name: flightschedule; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (1, 4, '2015-05-04', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (2, 4, '2015-05-04', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (3, 4, '2015-05-04', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (4, 4, '2015-05-04', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (5, 4, '2015-05-04', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (6, 4, '2015-05-04', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (7, 5, '2015-05-04', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (8, 5, '2015-05-04', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (9, 5, '2015-05-04', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (10, 5, '2015-05-04', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (11, 6, '2015-05-04', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (12, 6, '2015-05-04', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (13, 6, '2015-05-04', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (14, 6, '2015-05-04', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (15, 1, '2015-05-04', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (16, 1, '2015-05-04', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (17, 1, '2015-05-04', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (18, 1, '2015-05-04', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (19, 3, '2015-05-04', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (20, 3, '2015-05-04', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (21, 4, '2015-05-05', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (22, 4, '2015-05-05', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (23, 4, '2015-05-05', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (24, 4, '2015-05-05', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (25, 4, '2015-05-05', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (26, 4, '2015-05-05', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (27, 5, '2015-05-05', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (28, 5, '2015-05-05', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (29, 5, '2015-05-05', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (30, 5, '2015-05-05', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (31, 6, '2015-05-05', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (32, 6, '2015-05-05', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (33, 6, '2015-05-05', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (34, 6, '2015-05-05', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (35, 1, '2015-05-05', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (36, 1, '2015-05-05', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (37, 1, '2015-05-05', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (38, 1, '2015-05-05', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (39, 3, '2015-05-05', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (40, 3, '2015-05-05', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (41, 4, '2015-05-06', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (42, 4, '2015-05-06', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (43, 4, '2015-05-06', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (44, 4, '2015-05-06', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (45, 4, '2015-05-06', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (46, 4, '2015-05-06', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (47, 5, '2015-05-06', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (48, 5, '2015-05-06', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (49, 5, '2015-05-06', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (50, 5, '2015-05-06', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (51, 6, '2015-05-06', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (52, 6, '2015-05-06', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (53, 6, '2015-05-06', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (54, 6, '2015-05-06', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (55, 1, '2015-05-06', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (56, 1, '2015-05-06', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (57, 1, '2015-05-06', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (58, 1, '2015-05-06', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (59, 3, '2015-05-06', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (60, 3, '2015-05-06', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (61, 4, '2015-05-07', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (62, 4, '2015-05-07', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (63, 4, '2015-05-07', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (64, 4, '2015-05-07', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (65, 4, '2015-05-07', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (66, 4, '2015-05-07', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (67, 5, '2015-05-07', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (68, 5, '2015-05-07', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (69, 5, '2015-05-07', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (70, 5, '2015-05-07', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (71, 6, '2015-05-07', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (72, 6, '2015-05-07', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (73, 6, '2015-05-07', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (74, 6, '2015-05-07', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (75, 1, '2015-05-07', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (76, 1, '2015-05-07', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (77, 1, '2015-05-07', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (78, 1, '2015-05-07', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (79, 3, '2015-05-07', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (80, 3, '2015-05-07', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (81, 4, '2015-05-08', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (82, 4, '2015-05-08', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (83, 4, '2015-05-08', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (84, 4, '2015-05-08', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (85, 4, '2015-05-08', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (86, 4, '2015-05-08', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (87, 5, '2015-05-08', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (88, 5, '2015-05-08', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (89, 5, '2015-05-08', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (90, 5, '2015-05-08', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (91, 6, '2015-05-08', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (92, 6, '2015-05-08', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (93, 6, '2015-05-08', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (94, 6, '2015-05-08', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (95, 1, '2015-05-08', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (96, 1, '2015-05-08', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (97, 1, '2015-05-08', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (98, 1, '2015-05-08', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (99, 3, '2015-05-08', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (100, 3, '2015-05-08', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (101, 4, '2015-05-09', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (102, 4, '2015-05-09', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (103, 5, '2015-05-09', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (104, 5, '2015-05-09', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (105, 6, '2015-05-09', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (106, 6, '2015-05-09', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (107, 1, '2015-05-09', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (108, 1, '2015-05-09', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (109, 3, '2015-05-09', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (110, 3, '2015-05-09', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (111, 4, '2015-05-10', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (112, 4, '2015-05-10', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (113, 5, '2015-05-10', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (114, 5, '2015-05-10', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (115, 6, '2015-05-10', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (116, 6, '2015-05-10', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (117, 1, '2015-05-10', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (118, 1, '2015-05-10', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (119, 3, '2015-05-10', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (120, 3, '2015-05-10', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (121, 4, '2015-05-11', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (122, 4, '2015-05-11', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (123, 4, '2015-05-11', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (124, 4, '2015-05-11', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (125, 4, '2015-05-11', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (126, 4, '2015-05-11', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (127, 5, '2015-05-11', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (128, 5, '2015-05-11', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (129, 5, '2015-05-11', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (130, 5, '2015-05-11', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (131, 6, '2015-05-11', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (132, 6, '2015-05-11', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (133, 6, '2015-05-11', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (134, 6, '2015-05-11', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (135, 1, '2015-05-11', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (136, 1, '2015-05-11', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (137, 1, '2015-05-11', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (138, 1, '2015-05-11', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (139, 3, '2015-05-11', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (140, 3, '2015-05-11', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (141, 4, '2015-05-12', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (142, 4, '2015-05-12', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (143, 4, '2015-05-12', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (144, 4, '2015-05-12', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (145, 4, '2015-05-12', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (146, 4, '2015-05-12', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (147, 5, '2015-05-12', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (148, 5, '2015-05-12', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (149, 5, '2015-05-12', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (150, 5, '2015-05-12', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (151, 6, '2015-05-12', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (152, 6, '2015-05-12', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (153, 6, '2015-05-12', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (154, 6, '2015-05-12', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (155, 1, '2015-05-12', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (156, 1, '2015-05-12', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (157, 1, '2015-05-12', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (158, 1, '2015-05-12', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (159, 3, '2015-05-12', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (160, 3, '2015-05-12', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (161, 4, '2015-05-13', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (162, 4, '2015-05-13', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (163, 4, '2015-05-13', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (164, 4, '2015-05-13', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (165, 4, '2015-05-13', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (166, 4, '2015-05-13', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (167, 5, '2015-05-13', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (168, 5, '2015-05-13', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (169, 5, '2015-05-13', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (170, 5, '2015-05-13', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (171, 6, '2015-05-13', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (172, 6, '2015-05-13', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (173, 6, '2015-05-13', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (174, 6, '2015-05-13', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (175, 1, '2015-05-13', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (176, 1, '2015-05-13', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (177, 1, '2015-05-13', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (178, 1, '2015-05-13', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (179, 3, '2015-05-13', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (180, 3, '2015-05-13', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (181, 4, '2015-05-14', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (182, 4, '2015-05-14', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (183, 4, '2015-05-14', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (184, 4, '2015-05-14', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (185, 4, '2015-05-14', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (186, 4, '2015-05-14', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (187, 5, '2015-05-14', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (188, 5, '2015-05-14', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (189, 5, '2015-05-14', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (190, 5, '2015-05-14', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (191, 6, '2015-05-14', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (192, 6, '2015-05-14', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (193, 6, '2015-05-14', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (194, 6, '2015-05-14', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (195, 1, '2015-05-14', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (196, 1, '2015-05-14', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (197, 1, '2015-05-14', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (198, 1, '2015-05-14', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (199, 3, '2015-05-14', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (200, 3, '2015-05-14', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (201, 4, '2015-05-15', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (202, 4, '2015-05-15', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (203, 4, '2015-05-15', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (204, 4, '2015-05-15', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (205, 4, '2015-05-15', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (206, 4, '2015-05-15', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (207, 5, '2015-05-15', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (208, 5, '2015-05-15', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (209, 5, '2015-05-15', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (210, 5, '2015-05-15', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (211, 6, '2015-05-15', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (212, 6, '2015-05-15', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (213, 6, '2015-05-15', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (214, 6, '2015-05-15', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (215, 1, '2015-05-15', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (216, 1, '2015-05-15', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (217, 1, '2015-05-15', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (218, 1, '2015-05-15', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (219, 3, '2015-05-15', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (220, 3, '2015-05-15', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (221, 4, '2015-05-16', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (222, 4, '2015-05-16', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (223, 4, '2015-05-17', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (224, 4, '2015-05-17', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (225, 5, '2015-05-16', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (226, 5, '2015-05-16', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (227, 5, '2015-05-17', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (228, 5, '2015-05-17', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (229, 6, '2015-05-16', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (230, 6, '2015-05-16', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (231, 6, '2015-05-17', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (232, 6, '2015-05-17', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (233, 1, '2015-05-16', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (234, 1, '2015-05-16', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (235, 1, '2015-05-17', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (236, 1, '2015-05-17', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (237, 3, '2015-05-16', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (238, 3, '2015-05-16', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (239, 3, '2015-05-17', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (240, 3, '2015-05-17', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (241, 4, '2015-05-18', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (242, 4, '2015-05-18', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (243, 4, '2015-05-18', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (244, 4, '2015-05-18', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (245, 4, '2015-05-18', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (246, 4, '2015-05-18', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (247, 5, '2015-05-18', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (248, 5, '2015-05-18', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (249, 5, '2015-05-18', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (250, 5, '2015-05-18', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (251, 6, '2015-05-18', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (252, 6, '2015-05-18', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (253, 6, '2015-05-18', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (254, 6, '2015-05-18', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (255, 1, '2015-05-18', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (256, 1, '2015-05-18', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (257, 1, '2015-05-18', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (258, 1, '2015-05-18', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (259, 3, '2015-05-18', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (260, 3, '2015-05-18', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (261, 4, '2015-05-19', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (262, 4, '2015-05-19', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (263, 4, '2015-05-19', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (264, 4, '2015-05-19', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (265, 4, '2015-05-19', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (266, 4, '2015-05-19', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (267, 5, '2015-05-19', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (268, 5, '2015-05-19', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (269, 5, '2015-05-19', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (270, 5, '2015-05-19', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (271, 6, '2015-05-19', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (272, 6, '2015-05-19', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (273, 6, '2015-05-19', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (274, 6, '2015-05-19', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (275, 1, '2015-05-19', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (276, 1, '2015-05-19', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (277, 1, '2015-05-19', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (278, 1, '2015-05-19', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (279, 3, '2015-05-19', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (280, 3, '2015-05-19', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (281, 4, '2015-05-20', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (282, 4, '2015-05-20', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (283, 4, '2015-05-20', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (284, 4, '2015-05-20', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (285, 4, '2015-05-20', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (286, 4, '2015-05-20', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (287, 5, '2015-05-20', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (288, 5, '2015-05-20', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (289, 5, '2015-05-20', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (290, 5, '2015-05-20', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (291, 6, '2015-05-20', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (292, 6, '2015-05-20', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (293, 6, '2015-05-20', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (294, 6, '2015-05-20', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (295, 1, '2015-05-20', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (296, 1, '2015-05-20', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (297, 1, '2015-05-20', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (298, 1, '2015-05-20', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (299, 3, '2015-05-20', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (300, 3, '2015-05-20', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (301, 4, '2015-05-21', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (302, 4, '2015-05-21', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (303, 4, '2015-05-21', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (304, 4, '2015-05-21', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (305, 4, '2015-05-21', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (306, 4, '2015-05-21', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (307, 5, '2015-05-21', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (308, 5, '2015-05-21', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (309, 5, '2015-05-21', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (310, 5, '2015-05-21', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (311, 6, '2015-05-21', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (312, 6, '2015-05-21', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (313, 6, '2015-05-21', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (314, 6, '2015-05-21', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (315, 2, '2015-05-21', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (316, 2, '2015-05-21', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (317, 2, '2015-05-21', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (318, 2, '2015-05-21', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (319, 3, '2015-05-21', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (320, 3, '2015-05-21', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (321, 4, '2015-05-22', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (322, 4, '2015-05-22', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (323, 4, '2015-05-22', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (324, 4, '2015-05-22', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (325, 4, '2015-05-22', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (326, 4, '2015-05-22', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (327, 5, '2015-05-22', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (328, 5, '2015-05-22', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (329, 5, '2015-05-22', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (330, 5, '2015-05-22', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (331, 6, '2015-05-22', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (332, 6, '2015-05-22', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (333, 6, '2015-05-22', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (334, 6, '2015-05-22', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (335, 2, '2015-05-22', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (336, 2, '2015-05-22', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (337, 2, '2015-05-22', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (338, 2, '2015-05-22', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (339, 3, '2015-05-22', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (340, 3, '2015-05-22', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (341, 4, '2015-05-23', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (342, 4, '2015-05-23', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (343, 4, '2015-05-24', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (344, 4, '2015-05-24', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (345, 5, '2015-05-23', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (346, 5, '2015-05-23', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (347, 5, '2015-05-24', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (348, 5, '2015-05-24', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (349, 6, '2015-05-23', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (350, 6, '2015-05-23', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (351, 6, '2015-05-24', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (352, 6, '2015-05-24', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (353, 2, '2015-05-23', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (354, 2, '2015-05-23', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (355, 2, '2015-05-24', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (356, 2, '2015-05-24', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (357, 3, '2015-05-23', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (358, 3, '2015-05-23', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (359, 3, '2015-05-24', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (360, 3, '2015-05-24', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (361, 4, '2015-05-25', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (362, 4, '2015-05-25', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (363, 4, '2015-05-25', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (364, 4, '2015-05-25', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (365, 4, '2015-05-25', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (366, 4, '2015-05-25', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (367, 5, '2015-05-25', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (368, 5, '2015-05-25', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (369, 5, '2015-05-25', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (370, 5, '2015-05-25', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (371, 6, '2015-05-25', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (372, 6, '2015-05-25', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (373, 6, '2015-05-25', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (374, 6, '2015-05-25', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (375, 2, '2015-05-25', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (376, 2, '2015-05-25', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (377, 2, '2015-05-25', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (378, 2, '2015-05-25', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (379, 3, '2015-05-25', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (380, 3, '2015-05-25', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (381, 4, '2015-05-26', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (382, 4, '2015-05-26', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (383, 4, '2015-05-26', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (384, 4, '2015-05-26', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (385, 4, '2015-05-26', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (386, 4, '2015-05-26', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (387, 5, '2015-05-26', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (388, 5, '2015-05-26', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (389, 5, '2015-05-26', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (390, 5, '2015-05-26', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (391, 6, '2015-05-26', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (392, 6, '2015-05-26', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (393, 6, '2015-05-26', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (394, 6, '2015-05-26', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (395, 2, '2015-05-26', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (396, 2, '2015-05-26', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (397, 2, '2015-05-26', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (398, 2, '2015-05-26', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (399, 3, '2015-05-26', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (400, 3, '2015-05-26', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (401, 4, '2015-05-27', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (402, 4, '2015-05-27', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (403, 4, '2015-05-27', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (404, 4, '2015-05-27', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (405, 4, '2015-05-27', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (406, 4, '2015-05-27', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (407, 5, '2015-05-27', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (408, 5, '2015-05-27', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (409, 5, '2015-05-27', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (410, 5, '2015-05-27', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (411, 6, '2015-05-27', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (412, 6, '2015-05-27', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (413, 6, '2015-05-27', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (414, 6, '2015-05-27', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (415, 2, '2015-05-27', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (416, 2, '2015-05-27', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (417, 2, '2015-05-27', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (418, 2, '2015-05-27', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (419, 3, '2015-05-27', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (420, 3, '2015-05-27', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (421, 4, '2015-05-28', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (422, 4, '2015-05-28', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (423, 4, '2015-05-28', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (424, 4, '2015-05-28', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (425, 4, '2015-05-28', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (426, 4, '2015-05-28', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (427, 5, '2015-05-28', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (428, 5, '2015-05-28', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (429, 5, '2015-05-28', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (430, 5, '2015-05-28', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (431, 6, '2015-05-28', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (432, 6, '2015-05-28', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (433, 6, '2015-05-28', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (434, 6, '2015-05-28', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (435, 2, '2015-05-28', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (436, 2, '2015-05-28', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (437, 2, '2015-05-28', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (438, 2, '2015-05-28', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (439, 3, '2015-05-28', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (440, 3, '2015-05-28', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (441, 4, '2015-05-29', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (442, 4, '2015-05-29', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (443, 4, '2015-05-29', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (444, 4, '2015-05-29', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (445, 4, '2015-05-29', 5);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (446, 4, '2015-05-29', 6);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (447, 5, '2015-05-29', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (448, 5, '2015-05-29', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (449, 5, '2015-05-29', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (450, 5, '2015-05-29', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (451, 6, '2015-05-29', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (452, 6, '2015-05-29', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (453, 6, '2015-05-29', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (454, 6, '2015-05-29', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (455, 2, '2015-05-29', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (456, 2, '2015-05-29', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (457, 2, '2015-05-29', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (458, 2, '2015-05-29', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (459, 7, '2015-05-29', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (460, 7, '2015-05-29', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (461, 4, '2015-05-30', 1);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (462, 4, '2015-05-30', 2);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (463, 4, '2015-05-31', 3);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (464, 4, '2015-05-31', 4);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (465, 5, '2015-05-30', 7);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (466, 5, '2015-05-30', 8);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (467, 5, '2015-05-31', 9);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (468, 5, '2015-05-31', 10);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (469, 6, '2015-05-30', 11);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (470, 6, '2015-05-30', 12);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (471, 6, '2015-05-31', 13);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (472, 6, '2015-05-31', 14);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (473, 2, '2015-05-30', 15);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (474, 2, '2015-05-30', 16);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (475, 2, '2015-05-31', 17);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (476, 2, '2015-05-31', 18);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (477, 7, '2015-05-30', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (478, 7, '2015-05-30', 20);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (479, 7, '2015-05-31', 19);
INSERT INTO flightschedule (fschedule_id, aircraft_code, fdate, fprogram_id) VALUES (480, 7, '2015-05-31', 20);


--
-- TOC entry 2261 (class 0 OID 159759)
-- Dependencies: 183
-- Data for Name: flightsprogram; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 1, '2015-03-01', '2015-08-31', 1);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 2, '2015-03-01', '2015-08-31', 2);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 3, '2015-03-01', '2015-08-31', 3);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 4, '2015-03-01', '2015-08-31', 4);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 5, '2015-03-01', '2015-08-31', 5);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 6, '2015-03-01', '2015-08-31', 6);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 7, '2015-03-01', '2015-08-31', 7);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 8, '2015-03-01', '2015-08-31', 8);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 9, '2015-03-01', '2015-08-31', 9);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 10, '2015-03-01', '2015-08-31', 10);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 11, '2015-03-01', '2015-08-31', 11);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 12, '2015-03-01', '2015-08-31', 12);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 13, '2015-03-01', '2015-08-31', 13);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (3, 14, '2015-03-01', '2015-08-31', 14);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (1, 15, '2015-03-01', '2015-08-31', 15);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (1, 16, '2015-03-01', '2015-08-31', 16);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (1, 17, '2015-03-01', '2015-08-31', 17);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (1, 18, '2015-03-01', '2015-08-31', 18);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (2, 19, '2015-03-01', '2015-08-31', 19);
INSERT INTO flightsprogram (aircraft_type, flight_code, start_date, end_date, program_id) VALUES (2, 20, '2015-03-01', '2015-08-31', 20);


--
-- TOC entry 2262 (class 0 OID 159762)
-- Dependencies: 184
-- Data for Name: fsattendant; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO fsattendant (emp_id, native_lang) VALUES (18, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (19, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (20, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (21, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (30, 'en');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (32, 'fr');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (16, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (17, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (22, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (23, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (24, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (25, 'el');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (26, 'en');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (27, 'en');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (28, 'en');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (29, 'en');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (31, 'fr');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (33, 'fr');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (34, 'fr');
INSERT INTO fsattendant (emp_id, native_lang) VALUES (35, 'fr');


--
-- TOC entry 2263 (class 0 OID 159765)
-- Dependencies: 185
-- Data for Name: fsmonthlysalary; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO fsmonthlysalary (fs_id, dom_hours, int_hours, total, month, year) VALUES (1, 6.00000000000000000000, 0, 180.00000000000000000000, 5, 2015);


--
-- TOC entry 2264 (class 0 OID 159771)
-- Dependencies: 186
-- Data for Name: fspilots; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO fspilots (emp_id, degree) VALUES (1, 'Commander');
INSERT INTO fspilots (emp_id, degree) VALUES (2, 'Commander');
INSERT INTO fspilots (emp_id, degree) VALUES (3, 'Commander');
INSERT INTO fspilots (emp_id, degree) VALUES (4, 'Commander');
INSERT INTO fspilots (emp_id, degree) VALUES (5, 'Commander');
INSERT INTO fspilots (emp_id, degree) VALUES (6, 'Copilot');
INSERT INTO fspilots (emp_id, degree) VALUES (7, 'Copilot');
INSERT INTO fspilots (emp_id, degree) VALUES (8, 'Copilot');
INSERT INTO fspilots (emp_id, degree) VALUES (9, 'Copilot');
INSERT INTO fspilots (emp_id, degree) VALUES (10, 'Copilot');
INSERT INTO fspilots (emp_id, degree) VALUES (11, 'Officer');
INSERT INTO fspilots (emp_id, degree) VALUES (12, 'Officer');
INSERT INTO fspilots (emp_id, degree) VALUES (13, 'Officer');
INSERT INTO fspilots (emp_id, degree) VALUES (14, 'Officer');
INSERT INTO fspilots (emp_id, degree) VALUES (15, 'Officer');


--
-- TOC entry 2265 (class 0 OID 159775)
-- Dependencies: 187
-- Data for Name: fstaff; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (3, 'David', 'Dost', 'Pilot', '1970-03-25', '2310123147', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (1, 'Giannis', 'Gkouzionis', 'Pilot', '1970-12-14', '2310123456', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (5, 'Niklas', 'Benz', 'Pilot', '1968-08-06', '2310123369', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (7, 'John', 'Kennedy', 'Pilot', '1972-10-05', '2310456789', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (9, 'George', 'Kitsiou', 'Pilot', '1973-08-05', '2310456258', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (11, 'Bill', 'Kiriakakis', 'Pilot', '1972-02-02', '2310789123', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (13, 'Cristiano', 'Ronaldo', 'Pilot', '1976-11-06', '2310789789', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (17, 'Kate', 'Beckinsale', 'Attendant', '1982-10-25', '2311123456', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (19, 'Liv', 'Tyler', 'Attendant', '1981-06-03', '2311456123', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (21, 'Cate', 'Blanchett', 'Attendant', '1983-04-06', '2311789123', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (23, 'Carly', 'Pope', 'Attendant', '1982-11-11', '2311789789', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (25, 'Lena', 'Headey', 'Attendant', '1983-02-14', '2313123000', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (27, 'Margot', 'Robbie', 'Attendant', '1979-04-16', '2313789000', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (29, 'Violante', 'Placido', 'Attendant', '1980-06-18', '2313123789', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (31, 'Rachel', 'McAdams', 'Attendant', '1979-05-06', '2313456789', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (33, 'Amber', 'Stevens', 'Attendant', '1981-11-11', '2313789456', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (2, 'George', 'Best', 'Pilot', '1975-02-10', '2310123789', 'Admitou Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (4, 'Michael', 'Bender', 'Pilot', '1968-12-03', '2310123258', 'Adrianoupoleos Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (6, 'Bruce', 'Lee', 'Pilot', '1971-04-02', '2310456123', 'Aetorrachis Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (8, 'Nick', 'Papadopoulos', 'Pilot', '1966-06-03', '2310456147', 'Afidnaion Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (10, 'Bill', 'Dimakopoulos', 'Pilot', '1970-08-06', '2310456369', 'Agalianou Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (12, 'Zinedine', 'Zidane', 'Pilot', '1971-12-05', '2310789456', 'Agapinoros Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (14, 'Ryan', 'Giggs', 'Pilot', '1971-10-14', '2310159159', 'Chorton Tzortz Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (16, 'Natali', 'Portman', 'Attendant', '1980-05-15', '2310123564', 'Chrysiidos Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (18, 'Olivia', 'Wilde', 'Attendant', '1982-11-14', '2311123789', 'Chrysospiliotissis Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (20, 'Eva', 'Green', 'Attendant', '1982-10-09', '2311456789', 'Daidalidon Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (22, 'Kelly', 'Reilly', 'Attendant', '1983-04-07', '2311789456', 'Dimosthenous Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (24, 'Emily', 'Blunt', 'Attendant', '1982-12-12', '2311159753', 'Dioskouron Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (26, 'Amanda', 'Seyfried', 'Attendant', '1982-08-06', '2313456000', 'Dodekanisou Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (28, 'Jessica', 'Biel', 'Attendant', '1979-05-17', '2313123456', 'Evrystheos Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (30, 'Kristin', 'Kreuk', 'Attendant', '1980-09-02', '2313456123', 'Faiakon Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (32, 'Anna', 'Friel', 'Attendant', '1980-10-17', '2313789123', 'Gkyzi Nikolaou Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (34, 'Naomi', 'Watts', 'Attendant', '1978-03-02', '2313789789', 'Kalymnou Street');
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (15, 'Giannis', 'Papatrexas', 'Pilot', '1975-04-02', '2310104070', NULL);
INSERT INTO fstaff (id, fname, lname, job, birthdate, phone, address) VALUES (35, 'Vasia', 'Koutsomiti', 'Attendant', '1985-04-02', '2310114070', NULL);


--
-- TOC entry 2267 (class 0 OID 159791)
-- Dependencies: 191
-- Data for Name: gstaff; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (1, 'George', 'Giannakopoulos', 'Engineer', '1970-12-01', '2314123000', NULL, 2000);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (2, 'Giannis', 'Papadopoulos', 'Engineer', '1974-02-05', '2314123456', NULL, 2000);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (3, 'Dimitris', 'Charitos', 'Engineer', '1972-11-16', '2314123789', NULL, 2000);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (8, 'Maria', 'Papadopoulou', 'Employee', '1980-12-13', '2314789123', NULL, 1200);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (9, 'Helen', 'Papadimitriou', 'Employee', '1982-12-06', '2314789456', NULL, 1200);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (7, 'Emilia', 'Clarke', 'Employee', '1982-11-05', '2314456789', NULL, 1200);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (6, 'Amy', 'Acker', 'Employee', '1981-06-05', '2314456456', NULL, 1200);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (4, 'Tim', 'Robbins', 'Engineer', '1972-10-12', '2314456000', NULL, 2000);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (5, 'William', 'Hurt', 'Engineer', '1978-07-06', '2314456123', NULL, 1200);
INSERT INTO gstaff (id, fname, lname, job, birthdate, phone, address, salary) VALUES (10, 'Giana', 'Koutsodima', 'Employee', '1980-05-09', '2314159753', NULL, 1200);


--
-- TOC entry 2268 (class 0 OID 159797)
-- Dependencies: 192
-- Data for Name: language; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO language (lang_code, name) VALUES ('en', 'English');
INSERT INTO language (lang_code, name) VALUES ('el', 'Greek');
INSERT INTO language (lang_code, name) VALUES ('fr', 'French');
INSERT INTO language (lang_code, name) VALUES ('de', 'German');
INSERT INTO language (lang_code, name) VALUES ('it', 'Italian');
INSERT INTO language (lang_code, name) VALUES ('nl', 'Dutch');
INSERT INTO language (lang_code, name) VALUES ('pt', 'Portuguese');
INSERT INTO language (lang_code, name) VALUES ('ru', 'Russian');
INSERT INTO language (lang_code, name) VALUES ('es', 'Spanish');


--
-- TOC entry 2269 (class 0 OID 159800)
-- Dependencies: 193
-- Data for Name: madetransaction; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO madetransaction (id, t_id, type) VALUES (1, 1, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 2, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 3, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 4, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 5, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 6, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 7, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 8, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 9, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 10, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 11, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 12, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 13, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 14, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 15, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 16, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 17, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 18, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 19, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 20, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 21, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 22, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 23, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 24, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 25, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 26, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 27, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 28, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 29, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 30, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 31, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 32, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 33, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 34, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 35, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 36, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 37, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 38, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 39, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 40, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 41, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 42, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 43, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 44, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 45, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 46, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 47, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 48, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 49, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 50, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 51, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 52, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 53, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 54, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 55, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 56, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 57, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 58, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 59, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 60, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 61, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 62, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 63, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 64, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 65, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 66, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 67, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 68, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 69, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 70, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 71, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 72, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 73, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 74, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 75, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 76, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 77, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 78, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 79, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 80, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 81, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 82, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 83, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 84, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 85, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 86, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 87, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 88, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 89, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (1, 90, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 91, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 92, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 93, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 94, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 95, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 96, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 97, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 98, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 99, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 100, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 101, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 102, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 103, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 104, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 105, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 106, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 107, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 108, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 109, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 110, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 111, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 112, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 113, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 114, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 115, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 116, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 117, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 118, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 119, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (2, 120, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (7, 121, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (3, 122, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 123, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 124, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 125, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 126, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 127, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 128, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 129, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 130, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 131, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (9, 132, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (10, 133, 'gstaff');
INSERT INTO madetransaction (id, t_id, type) VALUES (3, 134, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (3, 135, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (5, 136, 'tagent');
INSERT INTO madetransaction (id, t_id, type) VALUES (5, 137, 'tagent');


--
-- TOC entry 2270 (class 0 OID 159803)
-- Dependencies: 194
-- Data for Name: reservation; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO reservation (tid) VALUES (8);
INSERT INTO reservation (tid) VALUES (9);
INSERT INTO reservation (tid) VALUES (10);
INSERT INTO reservation (tid) VALUES (21);
INSERT INTO reservation (tid) VALUES (22);
INSERT INTO reservation (tid) VALUES (23);
INSERT INTO reservation (tid) VALUES (24);
INSERT INTO reservation (tid) VALUES (25);
INSERT INTO reservation (tid) VALUES (39);
INSERT INTO reservation (tid) VALUES (40);
INSERT INTO reservation (tid) VALUES (51);
INSERT INTO reservation (tid) VALUES (52);
INSERT INTO reservation (tid) VALUES (53);
INSERT INTO reservation (tid) VALUES (54);
INSERT INTO reservation (tid) VALUES (55);
INSERT INTO reservation (tid) VALUES (66);
INSERT INTO reservation (tid) VALUES (67);
INSERT INTO reservation (tid) VALUES (68);
INSERT INTO reservation (tid) VALUES (69);
INSERT INTO reservation (tid) VALUES (70);
INSERT INTO reservation (tid) VALUES (81);
INSERT INTO reservation (tid) VALUES (82);
INSERT INTO reservation (tid) VALUES (83);
INSERT INTO reservation (tid) VALUES (84);
INSERT INTO reservation (tid) VALUES (85);
INSERT INTO reservation (tid) VALUES (96);
INSERT INTO reservation (tid) VALUES (97);
INSERT INTO reservation (tid) VALUES (98);
INSERT INTO reservation (tid) VALUES (99);
INSERT INTO reservation (tid) VALUES (100);
INSERT INTO reservation (tid) VALUES (115);
INSERT INTO reservation (tid) VALUES (127);
INSERT INTO reservation (tid) VALUES (128);
INSERT INTO reservation (tid) VALUES (129);
INSERT INTO reservation (tid) VALUES (130);
INSERT INTO reservation (tid) VALUES (131);


--
-- TOC entry 2271 (class 0 OID 159806)
-- Dependencies: 195
-- Data for Name: services; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 2272 (class 0 OID 159809)
-- Dependencies: 196
-- Data for Name: spoken_langs; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO spoken_langs (emp_id, lang_code) VALUES (16, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (16, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (17, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (17, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (18, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (18, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (19, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (19, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (20, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (20, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (21, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (21, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (22, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (22, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (23, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (23, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (24, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (24, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (25, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (25, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (26, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (26, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (27, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (27, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (28, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (28, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (29, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (29, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (30, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (30, 'fr');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (31, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (31, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (32, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (32, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (33, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (33, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (34, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (34, 'en');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (35, 'el');
INSERT INTO spoken_langs (emp_id, lang_code) VALUES (35, 'en');


--
-- TOC entry 2273 (class 0 OID 159812)
-- Dependencies: 197
-- Data for Name: staffschedule; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-04 07:00:00', 1);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-04 08:30:00', 2);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-04 13:00:00', 3);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-04 14:30:00', 4);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-04 19:00:00', 5);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-04 20:30:00', 6);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-04 07:00:00', 7);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-04 08:20:00', 8);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-04 18:00:00', 9);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-04 19:20:00', 10);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-04 08:15:00', 11);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-04 09:25:00', 12);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-04 15:00:00', 13);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-04 16:10:00', 14);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-04 10:30:00', 15);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-04 13:30:00', 16);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-04 20:30:00', 17);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-04 23:30:00', 18);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-04 10:30:00', 19);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-04 14:00:00', 20);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-05 07:00:00', 21);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-05 08:30:00', 22);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-05 13:00:00', 23);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-05 14:30:00', 24);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-05 19:00:00', 25);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-05 20:30:00', 26);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-05 07:00:00', 27);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-05 08:20:00', 28);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-05 18:00:00', 29);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-05 19:20:00', 30);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-05 08:15:00', 31);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-05 09:25:00', 32);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-05 15:00:00', 33);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-05 16:10:00', 34);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-05 10:30:00', 35);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-05 13:30:00', 36);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-05 20:30:00', 37);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-05 23:30:00', 38);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-05 10:30:00', 39);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-05 14:00:00', 40);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-06 07:00:00', 41);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-06 08:30:00', 42);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-06 13:00:00', 43);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-06 14:30:00', 44);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-06 19:00:00', 45);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-06 20:30:00', 46);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-06 07:00:00', 47);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-06 08:20:00', 48);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-06 18:00:00', 49);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-06 19:20:00', 50);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-06 08:15:00', 51);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-06 09:25:00', 52);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-06 15:00:00', 53);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-06 16:10:00', 54);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-06 10:30:00', 55);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-06 13:30:00', 56);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-06 20:30:00', 57);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-06 23:30:00', 58);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-06 10:30:00', 59);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-06 14:00:00', 60);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-07 07:00:00', 61);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-07 08:30:00', 62);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-07 13:00:00', 63);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-07 14:30:00', 64);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-07 19:00:00', 65);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-07 20:30:00', 66);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-07 07:00:00', 67);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-07 08:20:00', 68);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-07 18:00:00', 69);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-07 19:20:00', 70);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-07 08:15:00', 71);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-07 09:25:00', 72);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-07 15:00:00', 73);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-07 16:10:00', 74);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-07 10:30:00', 75);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-07 13:30:00', 76);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-07 20:30:00', 77);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-07 23:30:00', 78);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-07 10:30:00', 79);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-07 14:00:00', 80);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-08 07:00:00', 81);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-08 08:30:00', 82);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-08 13:00:00', 83);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-08 14:30:00', 84);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-08 19:00:00', 85);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-08 20:30:00', 86);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-08 07:00:00', 87);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-08 08:20:00', 88);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-08 18:00:00', 89);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-08 19:20:00', 90);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-08 08:15:00', 91);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-08 09:25:00', 92);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-08 15:00:00', 93);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-08 16:10:00', 94);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-08 10:30:00', 95);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-08 13:30:00', 96);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-08 20:30:00', 97);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-08 23:30:00', 98);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-08 10:30:00', 99);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-08 14:00:00', 100);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-09 07:00:00', 101);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-09 08:30:00', 102);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-09 07:00:00', 103);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-09 08:20:00', 104);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-09 08:15:00', 105);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-09 09:25:00', 106);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-09 10:30:00', 107);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-09 13:30:00', 108);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-09 10:30:00', 109);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-09 14:00:00', 110);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-10 13:00:00', 111);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-10 14:30:00', 112);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-10 18:00:00', 113);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-10 19:20:00', 114);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-10 15:15:00', 115);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-10 16:25:00', 116);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-10 20:30:00', 117);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-10 23:30:00', 118);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-10 10:30:00', 119);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-10 14:00:00', 120);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-11 07:00:00', 121);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-11 08:30:00', 122);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-11 13:00:00', 123);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-11 14:30:00', 124);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-11 19:00:00', 125);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-11 20:30:00', 126);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-11 07:00:00', 127);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-11 08:20:00', 128);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-11 18:00:00', 129);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-11 19:20:00', 130);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-11 08:15:00', 131);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-11 09:25:00', 132);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-11 15:00:00', 133);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-11 16:10:00', 134);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-11 10:30:00', 135);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-11 13:30:00', 136);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-11 20:30:00', 137);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-11 23:30:00', 138);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-11 10:30:00', 139);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-11 14:00:00', 140);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-12 07:00:00', 141);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-12 08:30:00', 142);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-12 13:00:00', 143);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-12 14:30:00', 144);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-12 19:00:00', 145);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-12 20:30:00', 146);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-12 07:00:00', 147);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-12 08:20:00', 148);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-12 18:00:00', 149);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-12 19:20:00', 150);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-12 08:15:00', 151);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-12 09:25:00', 152);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-12 15:00:00', 153);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-12 16:10:00', 154);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-12 10:30:00', 155);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-12 13:30:00', 156);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-12 20:30:00', 157);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-12 23:30:00', 158);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-12 10:30:00', 159);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-12 14:00:00', 160);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-13 07:00:00', 161);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-13 08:30:00', 162);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-13 13:00:00', 163);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-13 14:30:00', 164);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-13 19:00:00', 165);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-13 20:30:00', 166);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-13 07:00:00', 167);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-13 08:20:00', 168);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-13 18:00:00', 169);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-13 19:20:00', 170);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-13 08:15:00', 171);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-13 09:25:00', 172);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-13 15:00:00', 173);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-13 16:10:00', 174);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-13 10:30:00', 175);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-13 13:30:00', 176);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-13 20:30:00', 177);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-13 23:30:00', 178);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-13 10:30:00', 179);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-13 14:00:00', 180);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-14 07:00:00', 181);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-14 08:30:00', 182);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-14 13:00:00', 183);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-14 14:30:00', 184);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-14 19:00:00', 185);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-14 20:30:00', 186);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-14 07:00:00', 187);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-14 08:20:00', 188);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-14 18:00:00', 189);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-14 19:20:00', 190);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-14 08:15:00', 191);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-14 09:25:00', 192);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-14 15:00:00', 193);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-14 16:10:00', 194);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-14 10:30:00', 195);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-14 13:30:00', 196);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-14 20:30:00', 197);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-14 23:30:00', 198);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-14 10:30:00', 199);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-14 14:00:00', 200);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-15 07:00:00', 201);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-15 08:30:00', 202);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-15 13:00:00', 203);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-15 14:30:00', 204);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-15 19:00:00', 205);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-15 20:30:00', 206);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-15 07:00:00', 207);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-15 08:20:00', 208);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-15 18:00:00', 209);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-15 19:20:00', 210);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-15 08:15:00', 211);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-15 09:25:00', 212);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-15 15:00:00', 213);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-15 16:10:00', 214);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-15 10:30:00', 215);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-15 13:30:00', 216);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-15 20:30:00', 217);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-15 23:30:00', 218);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-15 10:30:00', 219);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-15 14:00:00', 220);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-16 07:00:00', 221);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-16 08:30:00', 222);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-16 07:00:00', 225);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-16 08:20:00', 226);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-16 08:15:00', 229);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-16 09:25:00', 230);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-16 10:30:00', 233);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-16 13:30:00', 234);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-16 10:30:00', 237);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-16 14:00:00', 238);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-17 13:00:00', 223);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-17 14:30:00', 224);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-17 18:00:00', 227);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-17 19:20:00', 228);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-17 15:15:00', 231);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-17 16:25:00', 232);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-17 20:30:00', 235);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-17 23:30:00', 236);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-17 10:30:00', 239);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-17 14:00:00', 240);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-18 07:00:00', 241);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-18 08:30:00', 242);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-18 13:00:00', 243);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-18 14:30:00', 244);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-18 19:00:00', 245);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-18 20:30:00', 246);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-18 07:00:00', 247);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-18 08:20:00', 248);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-18 18:00:00', 249);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-18 19:20:00', 250);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-18 08:15:00', 251);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-18 09:25:00', 252);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-18 15:00:00', 253);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-18 16:10:00', 254);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-18 10:30:00', 255);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-18 13:30:00', 256);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-18 20:30:00', 257);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-18 23:30:00', 258);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-18 10:30:00', 259);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-18 14:00:00', 260);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-19 07:00:00', 261);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-19 08:30:00', 262);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-19 13:00:00', 263);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-19 14:30:00', 264);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-19 19:00:00', 265);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-19 20:30:00', 266);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-19 07:00:00', 267);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-19 08:20:00', 268);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-19 18:00:00', 269);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-19 19:20:00', 270);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-19 08:15:00', 271);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-19 09:25:00', 272);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-19 15:00:00', 273);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-19 16:10:00', 274);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-19 10:30:00', 275);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-19 13:30:00', 276);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-19 20:30:00', 277);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-19 23:30:00', 278);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-19 10:30:00', 279);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-19 14:00:00', 280);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-20 07:00:00', 281);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-20 08:30:00', 282);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-20 13:00:00', 283);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-20 14:30:00', 284);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-20 19:00:00', 285);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-20 20:30:00', 286);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-20 07:00:00', 287);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-20 08:20:00', 288);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-20 18:00:00', 289);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-20 19:20:00', 290);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-20 08:15:00', 291);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-20 09:25:00', 292);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-20 15:00:00', 293);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-20 16:10:00', 294);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-20 10:30:00', 295);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-20 13:30:00', 296);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-20 20:30:00', 297);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-20 23:30:00', 298);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-20 10:30:00', 299);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-20 14:00:00', 300);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-21 07:00:00', 301);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-21 08:30:00', 302);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-21 13:00:00', 303);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-21 14:30:00', 304);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-21 19:00:00', 305);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-21 20:30:00', 306);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-21 07:00:00', 307);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-21 08:20:00', 308);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-21 18:00:00', 309);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-21 19:20:00', 310);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-21 08:15:00', 311);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-21 09:25:00', 312);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-21 15:00:00', 313);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-21 16:10:00', 314);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-21 10:30:00', 315);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-21 13:30:00', 316);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-21 20:30:00', 317);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-21 23:30:00', 318);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-21 10:30:00', 319);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-21 14:00:00', 320);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-22 07:00:00', 321);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-22 08:30:00', 322);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-22 13:00:00', 323);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-22 14:30:00', 324);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-22 19:00:00', 325);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-22 20:30:00', 326);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-22 07:00:00', 327);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-22 08:20:00', 328);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-22 18:00:00', 329);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-22 19:20:00', 330);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-22 08:15:00', 331);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-22 09:25:00', 332);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-22 15:00:00', 333);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-22 16:10:00', 334);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-22 10:30:00', 335);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-22 13:30:00', 336);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-22 20:30:00', 337);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-22 23:30:00', 338);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-22 10:30:00', 339);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-22 14:00:00', 340);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-23 07:00:00', 341);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-23 08:30:00', 342);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-23 07:00:00', 345);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-23 08:20:00', 346);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-23 08:15:00', 349);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-23 09:25:00', 350);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-23 10:30:00', 353);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-23 13:30:00', 354);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-23 10:30:00', 357);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-23 14:00:00', 358);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-24 13:00:00', 343);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-24 14:30:00', 344);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-24 18:00:00', 347);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-24 19:20:00', 348);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-24 15:15:00', 351);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-24 16:25:00', 352);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-24 20:30:00', 355);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-24 23:30:00', 356);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-24 10:30:00', 359);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-24 14:00:00', 360);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-25 07:00:00', 361);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-25 08:30:00', 362);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-25 13:00:00', 363);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-25 14:30:00', 364);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-25 19:00:00', 365);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-25 20:30:00', 366);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-25 07:00:00', 367);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-25 08:20:00', 368);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-25 18:00:00', 369);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-25 19:20:00', 370);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-25 08:15:00', 371);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-25 09:25:00', 372);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-25 15:00:00', 373);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-25 16:10:00', 374);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-25 10:30:00', 375);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-25 13:30:00', 376);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-25 20:30:00', 377);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-25 23:30:00', 378);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-25 10:30:00', 379);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-25 14:00:00', 380);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-26 07:00:00', 381);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-26 08:30:00', 382);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-26 13:00:00', 383);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-26 14:30:00', 384);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-26 19:00:00', 385);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-26 20:30:00', 386);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-26 07:00:00', 387);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-26 08:20:00', 388);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-26 18:00:00', 389);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-26 19:20:00', 390);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-26 08:15:00', 391);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-26 09:25:00', 392);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-26 15:00:00', 393);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-26 16:10:00', 394);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-26 10:30:00', 395);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-26 13:30:00', 396);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-26 20:30:00', 397);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (4, '2015-05-26 23:30:00', 398);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-26 10:30:00', 399);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-26 14:00:00', 400);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-27 07:00:00', 401);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-27 08:30:00', 402);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-27 13:00:00', 403);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-27 14:30:00', 404);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-27 19:00:00', 405);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (1, '2015-05-27 20:30:00', 406);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-27 07:00:00', 407);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-27 08:20:00', 408);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-27 18:00:00', 409);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (2, '2015-05-27 19:20:00', 410);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-27 08:15:00', 411);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-27 09:25:00', 412);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-27 15:00:00', 413);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (3, '2015-05-27 16:10:00', 414);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-27 10:30:00', 415);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-27 13:30:00', 416);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-27 20:30:00', 417);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-27 23:30:00', 418);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-27 10:30:00', 419);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (5, '2015-05-27 14:00:00', 420);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-28 07:00:00', 421);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-28 08:30:00', 422);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-28 13:00:00', 423);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-28 14:30:00', 424);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-28 19:00:00', 425);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-28 20:30:00', 426);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-28 07:00:00', 427);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-28 08:20:00', 428);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-28 18:00:00', 429);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-28 19:20:00', 430);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-28 08:15:00', 431);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-28 09:25:00', 432);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-28 15:00:00', 433);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-28 16:10:00', 434);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-28 10:30:00', 435);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-28 13:30:00', 436);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-28 20:30:00', 437);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (6, '2015-05-28 23:30:00', 438);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-28 10:30:00', 439);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-28 14:00:00', 440);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-29 07:00:00', 441);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-29 08:30:00', 442);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-29 13:00:00', 443);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-29 14:30:00', 444);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-29 19:00:00', 445);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-29 20:30:00', 446);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-29 07:00:00', 447);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-29 08:20:00', 448);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-29 18:00:00', 449);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-29 19:20:00', 450);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-29 08:15:00', 451);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-29 09:25:00', 452);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-29 15:00:00', 453);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-29 16:10:00', 454);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-29 10:30:00', 455);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-29 13:30:00', 456);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-29 20:30:00', 457);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-29 23:30:00', 458);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-29 10:30:00', 459);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-29 14:00:00', 460);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-30 07:00:00', 461);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (7, '2015-05-30 08:30:00', 462);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-30 07:00:00', 465);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-30 08:20:00', 466);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-30 08:15:00', 469);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-30 09:25:00', 470);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-30 10:30:00', 473);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (11, '2015-05-30 13:30:00', 474);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-30 10:30:00', 477);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (10, '2015-05-30 14:00:00', 478);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-31 13:00:00', 463);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (12, '2015-05-31 14:30:00', 464);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-31 18:00:00', 467);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (8, '2015-05-31 19:20:00', 468);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-31 15:15:00', 471);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (9, '2015-05-31 16:25:00', 472);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-31 20:30:00', 475);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (13, '2015-05-31 23:30:00', 476);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-31 10:30:00', 479);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (14, '2015-05-31 14:00:00', 480);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-04 07:00:00', 1);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-04 08:30:00', 2);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-04 13:00:00', 3);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-04 14:30:00', 4);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-04 19:00:00', 5);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-04 20:30:00', 6);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-04 07:00:00', 7);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-04 08:20:00', 8);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-04 18:00:00', 9);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-04 19:20:00', 10);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-04 08:15:00', 11);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-04 09:25:00', 12);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-04 15:00:00', 13);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-04 16:10:00', 14);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-04 10:30:00', 15);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-04 13:30:00', 16);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-04 20:30:00', 17);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-04 23:30:00', 18);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-04 10:30:00', 19);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-04 14:00:00', 20);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-05 07:00:00', 21);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-05 08:30:00', 22);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-05 13:00:00', 23);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-05 14:30:00', 24);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-05 19:00:00', 25);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-05 20:30:00', 26);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-05 07:00:00', 27);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-05 08:20:00', 28);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-05 18:00:00', 29);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-05 19:20:00', 30);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-05 08:15:00', 31);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-05 09:25:00', 32);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-05 15:00:00', 33);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-05 16:10:00', 34);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-05 10:30:00', 35);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-05 13:30:00', 36);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-05 20:30:00', 37);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-05 23:30:00', 38);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-05 10:30:00', 39);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-05 14:00:00', 40);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-06 07:00:00', 41);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-06 08:30:00', 42);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-06 13:00:00', 43);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-06 14:30:00', 44);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-06 19:00:00', 45);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-06 20:30:00', 46);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-06 07:00:00', 47);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-06 08:20:00', 48);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-06 18:00:00', 49);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-06 19:20:00', 50);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-06 08:15:00', 51);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-06 09:25:00', 52);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-06 15:00:00', 53);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-06 16:10:00', 54);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-06 10:30:00', 55);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-06 13:30:00', 56);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-06 20:30:00', 57);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-06 23:30:00', 58);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-06 10:30:00', 59);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-06 14:00:00', 60);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-07 07:00:00', 61);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-07 08:30:00', 62);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-07 13:00:00', 63);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-07 14:30:00', 64);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-07 19:00:00', 65);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-07 20:30:00', 66);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-07 07:00:00', 67);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-07 08:20:00', 68);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-07 18:00:00', 69);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-07 19:20:00', 70);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-07 08:15:00', 71);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-07 09:25:00', 72);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-07 15:00:00', 73);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-07 16:10:00', 74);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-07 10:30:00', 75);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-07 13:30:00', 76);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-07 20:30:00', 77);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-07 23:30:00', 78);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-07 10:30:00', 79);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-07 14:00:00', 80);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-08 07:00:00', 81);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-08 08:30:00', 82);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-08 13:00:00', 83);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-08 14:30:00', 84);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-08 19:00:00', 85);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-08 20:30:00', 86);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-08 07:00:00', 87);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-08 08:20:00', 88);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-08 18:00:00', 89);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-08 19:20:00', 90);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-08 08:15:00', 91);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-08 09:25:00', 92);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-08 15:00:00', 93);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-08 16:10:00', 94);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-08 10:30:00', 95);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-08 13:30:00', 96);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-08 20:30:00', 97);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-08 23:30:00', 98);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-08 10:30:00', 99);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-08 14:00:00', 100);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-09 07:00:00', 101);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-09 08:30:00', 102);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-09 07:00:00', 103);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-09 08:20:00', 104);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-09 08:15:00', 105);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-09 09:25:00', 106);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-09 10:30:00', 107);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-09 13:30:00', 108);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-09 10:30:00', 109);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-09 14:00:00', 110);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-10 13:00:00', 111);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-10 14:30:00', 112);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-10 18:00:00', 113);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-10 19:20:00', 114);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-10 15:15:00', 115);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-10 16:25:00', 116);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-10 20:30:00', 117);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-10 23:30:00', 118);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-10 10:30:00', 119);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-10 14:00:00', 120);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-11 07:00:00', 121);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-11 08:30:00', 122);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-11 13:00:00', 123);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-11 14:30:00', 124);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-11 19:00:00', 125);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-11 20:30:00', 126);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-11 07:00:00', 127);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-11 08:20:00', 128);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-11 18:00:00', 129);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-11 19:20:00', 130);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-11 08:15:00', 131);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-11 09:25:00', 132);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-11 15:00:00', 133);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-11 16:10:00', 134);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-11 10:30:00', 135);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-11 13:30:00', 136);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-11 20:30:00', 137);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-11 23:30:00', 138);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-11 10:30:00', 139);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-11 14:00:00', 140);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-12 07:00:00', 141);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-12 08:30:00', 142);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-12 13:00:00', 143);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-12 14:30:00', 144);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-12 19:00:00', 145);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-12 20:30:00', 146);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-12 07:00:00', 147);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-12 08:20:00', 148);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-12 18:00:00', 149);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-12 19:20:00', 150);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-12 08:15:00', 151);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-12 09:25:00', 152);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-12 15:00:00', 153);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-12 16:10:00', 154);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-12 10:30:00', 155);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-12 13:30:00', 156);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-12 20:30:00', 157);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-12 23:30:00', 158);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-12 10:30:00', 159);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-12 14:00:00', 160);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-13 07:00:00', 161);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-13 08:30:00', 162);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-13 13:00:00', 163);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-13 14:30:00', 164);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-13 19:00:00', 165);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-13 20:30:00', 166);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-13 07:00:00', 167);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-13 08:20:00', 168);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-13 18:00:00', 169);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-13 19:20:00', 170);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-13 08:15:00', 171);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-13 09:25:00', 172);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-13 15:00:00', 173);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-13 16:10:00', 174);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-13 10:30:00', 175);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-13 13:30:00', 176);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-13 20:30:00', 177);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-13 23:30:00', 178);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-13 10:30:00', 179);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-13 14:00:00', 180);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-14 07:00:00', 181);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-14 08:30:00', 182);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-14 13:00:00', 183);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-14 14:30:00', 184);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-14 19:00:00', 185);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-14 20:30:00', 186);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-14 07:00:00', 187);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-14 08:20:00', 188);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-14 18:00:00', 189);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-14 19:20:00', 190);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-14 08:15:00', 191);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-14 09:25:00', 192);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-14 15:00:00', 193);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-14 16:10:00', 194);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-14 10:30:00', 195);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-14 13:30:00', 196);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-14 20:30:00', 197);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-14 23:30:00', 198);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-14 10:30:00', 199);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-14 14:00:00', 200);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-15 07:00:00', 201);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-15 08:30:00', 202);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-15 13:00:00', 203);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-15 14:30:00', 204);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-15 19:00:00', 205);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-15 20:30:00', 206);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-15 07:00:00', 207);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-15 08:20:00', 208);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-15 18:00:00', 209);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-15 19:20:00', 210);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-15 08:15:00', 211);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-15 09:25:00', 212);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-15 15:00:00', 213);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-15 16:10:00', 214);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-15 10:30:00', 215);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-15 13:30:00', 216);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-15 20:30:00', 217);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-15 23:30:00', 218);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-15 10:30:00', 219);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-15 14:00:00', 220);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-16 07:00:00', 221);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-16 08:30:00', 222);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-16 07:00:00', 225);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-16 08:20:00', 226);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-16 08:15:00', 229);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-16 09:25:00', 230);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-16 10:30:00', 233);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-16 13:30:00', 234);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-16 10:30:00', 237);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-16 14:00:00', 238);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-17 13:00:00', 223);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-17 14:30:00', 224);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-17 18:00:00', 227);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-17 19:20:00', 228);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-17 15:15:00', 231);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-17 16:25:00', 232);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-17 20:30:00', 235);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-17 23:30:00', 236);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-17 10:30:00', 239);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-17 14:00:00', 240);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-18 07:00:00', 241);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-18 08:30:00', 242);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-18 13:00:00', 243);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-18 14:30:00', 244);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-18 19:00:00', 245);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-18 20:30:00', 246);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-18 07:00:00', 247);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-18 08:20:00', 248);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-18 18:00:00', 249);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-18 19:20:00', 250);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-18 08:15:00', 251);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-18 09:25:00', 252);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-18 15:00:00', 253);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-18 16:10:00', 254);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-18 10:30:00', 255);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-18 13:30:00', 256);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-18 20:30:00', 257);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-18 23:30:00', 258);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-18 10:30:00', 259);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-18 14:00:00', 260);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-19 07:00:00', 261);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-19 08:30:00', 262);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-19 13:00:00', 263);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-19 14:30:00', 264);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-19 19:00:00', 265);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-19 20:30:00', 266);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-19 07:00:00', 267);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-19 08:20:00', 268);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-19 18:00:00', 269);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-19 19:20:00', 270);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-19 08:15:00', 271);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-19 09:25:00', 272);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-19 15:00:00', 273);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-19 16:10:00', 274);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-19 10:30:00', 275);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-19 13:30:00', 276);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-19 20:30:00', 277);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-19 23:30:00', 278);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-19 10:30:00', 279);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-19 14:00:00', 280);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-20 07:00:00', 281);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-20 08:30:00', 282);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-20 13:00:00', 283);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-20 14:30:00', 284);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-20 19:00:00', 285);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-20 20:30:00', 286);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-20 07:00:00', 287);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-20 08:20:00', 288);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-20 18:00:00', 289);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-20 19:20:00', 290);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-20 08:15:00', 291);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-20 09:25:00', 292);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-20 15:00:00', 293);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-20 16:10:00', 294);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-20 10:30:00', 295);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-20 13:30:00', 296);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-20 20:30:00', 297);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-20 23:30:00', 298);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-20 10:30:00', 299);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-20 14:00:00', 300);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-21 07:00:00', 301);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-21 08:30:00', 302);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-21 13:00:00', 303);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-21 14:30:00', 304);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-21 19:00:00', 305);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-21 20:30:00', 306);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-21 07:00:00', 307);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-21 08:20:00', 308);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-21 18:00:00', 309);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-21 19:20:00', 310);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-21 08:15:00', 311);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-21 09:25:00', 312);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-21 15:00:00', 313);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-21 16:10:00', 314);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-21 10:30:00', 315);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-21 13:30:00', 316);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-21 20:30:00', 317);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-21 23:30:00', 318);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-21 10:30:00', 319);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-21 14:00:00', 320);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-22 07:00:00', 321);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-22 08:30:00', 322);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-22 13:00:00', 323);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-22 14:30:00', 324);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-22 19:00:00', 325);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-22 20:30:00', 326);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-22 07:00:00', 327);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-22 08:20:00', 328);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-22 18:00:00', 329);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-22 19:20:00', 330);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-22 08:15:00', 331);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-22 09:25:00', 332);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-22 15:00:00', 333);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-22 16:10:00', 334);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-22 10:30:00', 335);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-22 13:30:00', 336);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-22 20:30:00', 337);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-22 23:30:00', 338);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-22 10:30:00', 339);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-22 14:00:00', 340);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-23 07:00:00', 341);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-23 08:30:00', 342);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-23 07:00:00', 345);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-23 08:20:00', 346);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-23 08:15:00', 349);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-23 09:25:00', 350);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-23 10:30:00', 353);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-23 13:30:00', 354);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-23 10:30:00', 357);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-23 14:00:00', 358);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-24 13:00:00', 343);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-24 14:30:00', 344);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-24 18:00:00', 347);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-24 19:20:00', 348);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-24 15:15:00', 351);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-24 16:25:00', 352);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-24 20:30:00', 355);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-24 23:30:00', 356);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-24 10:30:00', 359);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-24 14:00:00', 360);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-25 07:00:00', 361);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-25 08:30:00', 362);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-25 13:00:00', 363);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-25 14:30:00', 364);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-25 19:00:00', 365);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-25 20:30:00', 366);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-25 07:00:00', 367);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-25 08:20:00', 368);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-25 18:00:00', 369);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-25 19:20:00', 370);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-25 08:15:00', 371);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-25 09:25:00', 372);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-25 15:00:00', 373);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-25 16:10:00', 374);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-25 10:30:00', 375);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-25 13:30:00', 376);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-25 20:30:00', 377);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-25 23:30:00', 378);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-25 10:30:00', 379);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-25 14:00:00', 380);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-26 07:00:00', 381);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-26 08:30:00', 382);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-26 13:00:00', 383);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-26 14:30:00', 384);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-26 19:00:00', 385);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-26 20:30:00', 386);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-26 07:00:00', 387);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-26 08:20:00', 388);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-26 18:00:00', 389);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-26 19:20:00', 390);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-26 08:15:00', 391);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-26 09:25:00', 392);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-26 15:00:00', 393);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-26 16:10:00', 394);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-26 10:30:00', 395);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-26 13:30:00', 396);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-26 20:30:00', 397);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-26 23:30:00', 398);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-26 10:30:00', 399);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-26 14:00:00', 400);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-27 07:00:00', 401);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-27 08:30:00', 402);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-27 13:00:00', 403);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-27 14:30:00', 404);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-27 19:00:00', 405);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-27 20:30:00', 406);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-27 07:00:00', 407);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-27 08:20:00', 408);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-27 18:00:00', 409);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-27 19:20:00', 410);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-27 08:15:00', 411);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-27 09:25:00', 412);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-27 15:00:00', 413);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-27 16:10:00', 414);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-27 10:30:00', 415);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-27 13:30:00', 416);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-27 20:30:00', 417);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (29, '2015-05-27 23:30:00', 418);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-27 10:30:00', 419);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (33, '2015-05-27 14:00:00', 420);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-28 07:00:00', 421);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-28 08:30:00', 422);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-28 13:00:00', 423);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-28 14:30:00', 424);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-28 19:00:00', 425);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (17, '2015-05-28 20:30:00', 426);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-28 07:00:00', 427);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-28 08:20:00', 428);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-28 18:00:00', 429);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (21, '2015-05-28 19:20:00', 430);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-28 08:15:00', 431);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-28 09:25:00', 432);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-28 15:00:00', 433);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (25, '2015-05-28 16:10:00', 434);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-28 10:30:00', 435);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-28 13:30:00', 436);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-28 20:30:00', 437);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-28 23:30:00', 438);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-28 10:30:00', 439);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-28 14:00:00', 440);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-29 07:00:00', 441);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-29 08:30:00', 442);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-29 13:00:00', 443);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-29 14:30:00', 444);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-29 19:00:00', 445);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-29 20:30:00', 446);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-29 07:00:00', 447);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-29 08:20:00', 448);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-29 18:00:00', 449);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-29 19:20:00', 450);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-29 08:15:00', 451);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-29 09:25:00', 452);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-29 15:00:00', 453);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-29 16:10:00', 454);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-29 10:30:00', 455);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-29 13:30:00', 456);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-29 20:30:00', 457);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-29 23:30:00', 458);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-29 10:30:00', 459);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-29 14:00:00', 460);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-04 07:00:00', 1);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-04 08:30:00', 2);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-04 13:00:00', 3);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-04 14:30:00', 4);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-04 19:00:00', 5);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-04 20:30:00', 6);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-04 07:00:00', 7);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-04 08:20:00', 8);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-04 18:00:00', 9);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-04 19:20:00', 10);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-04 08:15:00', 11);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-04 09:25:00', 12);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-04 15:00:00', 13);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-04 16:10:00', 14);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-04 10:30:00', 15);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-04 13:30:00', 16);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-04 20:30:00', 17);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-04 23:30:00', 18);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-04 10:30:00', 19);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-04 14:00:00', 20);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-05 07:00:00', 21);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-05 08:30:00', 22);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-05 13:00:00', 23);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-05 14:30:00', 24);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-05 19:00:00', 25);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-05 20:30:00', 26);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-05 07:00:00', 27);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-05 08:20:00', 28);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-05 18:00:00', 29);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-05 19:20:00', 30);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-05 08:15:00', 31);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-05 09:25:00', 32);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-05 15:00:00', 33);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-05 16:10:00', 34);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-05 10:30:00', 35);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-05 13:30:00', 36);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-05 20:30:00', 37);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-05 23:30:00', 38);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-05 10:30:00', 39);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-05 14:00:00', 40);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-06 07:00:00', 41);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-06 08:30:00', 42);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-06 13:00:00', 43);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-06 14:30:00', 44);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-06 19:00:00', 45);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-06 20:30:00', 46);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-06 07:00:00', 47);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-06 08:20:00', 48);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-06 18:00:00', 49);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-06 19:20:00', 50);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-06 08:15:00', 51);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-06 09:25:00', 52);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-06 15:00:00', 53);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-06 16:10:00', 54);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-06 10:30:00', 55);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-06 13:30:00', 56);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-06 20:30:00', 57);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-06 23:30:00', 58);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-06 10:30:00', 59);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-06 14:00:00', 60);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-07 07:00:00', 61);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-07 08:30:00', 62);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-07 13:00:00', 63);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-07 14:30:00', 64);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-07 19:00:00', 65);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-07 20:30:00', 66);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-07 07:00:00', 67);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-07 08:20:00', 68);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-07 18:00:00', 69);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-07 19:20:00', 70);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-07 08:15:00', 71);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-07 09:25:00', 72);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-07 15:00:00', 73);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-07 16:10:00', 74);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-07 10:30:00', 75);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-07 13:30:00', 76);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-07 20:30:00', 77);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-07 23:30:00', 78);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-07 10:30:00', 79);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-07 14:00:00', 80);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-08 07:00:00', 81);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-08 08:30:00', 82);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-08 13:00:00', 83);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-08 14:30:00', 84);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-08 19:00:00', 85);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-08 20:30:00', 86);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-08 07:00:00', 87);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-08 08:20:00', 88);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-08 18:00:00', 89);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-08 19:20:00', 90);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-08 08:15:00', 91);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-08 09:25:00', 92);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-08 15:00:00', 93);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-08 16:10:00', 94);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-08 10:30:00', 95);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-08 13:30:00', 96);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-08 20:30:00', 97);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-08 23:30:00', 98);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-08 10:30:00', 99);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-08 14:00:00', 100);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-09 07:00:00', 101);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-09 08:30:00', 102);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-09 07:00:00', 103);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-09 08:20:00', 104);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-09 08:15:00', 105);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-09 09:25:00', 106);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-09 10:30:00', 107);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-09 13:30:00', 108);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-09 10:30:00', 109);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-09 14:00:00', 110);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-10 13:00:00', 111);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-10 14:30:00', 112);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-10 18:00:00', 113);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-10 19:20:00', 114);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-10 15:15:00', 115);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-10 16:25:00', 116);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-10 20:30:00', 117);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-10 23:30:00', 118);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-10 10:30:00', 119);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-10 14:00:00', 120);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-11 07:00:00', 121);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-11 08:30:00', 122);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-11 13:00:00', 123);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-11 14:30:00', 124);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-11 19:00:00', 125);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-11 20:30:00', 126);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-11 07:00:00', 127);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-11 08:20:00', 128);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-11 18:00:00', 129);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-11 19:20:00', 130);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-11 08:15:00', 131);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-11 09:25:00', 132);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-11 15:00:00', 133);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-11 16:10:00', 134);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-11 10:30:00', 135);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-11 13:30:00', 136);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-11 20:30:00', 137);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-11 23:30:00', 138);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-11 10:30:00', 139);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-11 14:00:00', 140);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-12 07:00:00', 141);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-12 08:30:00', 142);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-12 13:00:00', 143);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-12 14:30:00', 144);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-12 19:00:00', 145);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-12 20:30:00', 146);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-12 07:00:00', 147);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-12 08:20:00', 148);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-12 18:00:00', 149);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-12 19:20:00', 150);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-12 08:15:00', 151);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-12 09:25:00', 152);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-12 15:00:00', 153);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-12 16:10:00', 154);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-12 10:30:00', 155);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-12 13:30:00', 156);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-12 20:30:00', 157);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-12 23:30:00', 158);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-12 10:30:00', 159);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-12 14:00:00', 160);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-13 07:00:00', 161);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-13 08:30:00', 162);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-13 13:00:00', 163);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-13 14:30:00', 164);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-13 19:00:00', 165);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-13 20:30:00', 166);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-13 07:00:00', 167);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-13 08:20:00', 168);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-13 18:00:00', 169);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-13 19:20:00', 170);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-13 08:15:00', 171);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-13 09:25:00', 172);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-13 15:00:00', 173);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-13 16:10:00', 174);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-13 10:30:00', 175);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-13 13:30:00', 176);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-13 20:30:00', 177);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-13 23:30:00', 178);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-13 10:30:00', 179);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-13 14:00:00', 180);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-14 07:00:00', 181);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-14 08:30:00', 182);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-14 13:00:00', 183);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-14 14:30:00', 184);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-14 19:00:00', 185);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-14 20:30:00', 186);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-14 07:00:00', 187);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-14 08:20:00', 188);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-14 18:00:00', 189);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-14 19:20:00', 190);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-14 08:15:00', 191);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-14 09:25:00', 192);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-14 15:00:00', 193);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-14 16:10:00', 194);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-14 10:30:00', 195);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-14 13:30:00', 196);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-14 20:30:00', 197);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-14 23:30:00', 198);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-14 10:30:00', 199);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-14 14:00:00', 200);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-15 07:00:00', 201);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-15 08:30:00', 202);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-15 13:00:00', 203);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-15 14:30:00', 204);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-15 19:00:00', 205);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-15 20:30:00', 206);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-15 07:00:00', 207);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-15 08:20:00', 208);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-15 18:00:00', 209);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-15 19:20:00', 210);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-15 08:15:00', 211);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-15 09:25:00', 212);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-15 15:00:00', 213);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-15 16:10:00', 214);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-15 10:30:00', 215);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-15 13:30:00', 216);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-15 20:30:00', 217);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-15 23:30:00', 218);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-15 10:30:00', 219);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-15 14:00:00', 220);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-16 07:00:00', 221);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-16 08:30:00', 222);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-16 07:00:00', 225);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-16 08:20:00', 226);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-16 08:15:00', 229);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-16 09:25:00', 230);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-16 10:30:00', 233);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-16 13:30:00', 234);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-16 10:30:00', 237);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-16 14:00:00', 238);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-17 13:00:00', 223);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-17 14:30:00', 224);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-17 18:00:00', 227);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-17 19:20:00', 228);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-17 15:15:00', 231);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-17 16:25:00', 232);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-17 20:30:00', 235);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-17 23:30:00', 236);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-17 10:30:00', 239);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-17 14:00:00', 240);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-18 07:00:00', 241);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-18 08:30:00', 242);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-18 13:00:00', 243);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-18 14:30:00', 244);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-18 19:00:00', 245);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-18 20:30:00', 246);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-18 07:00:00', 247);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-18 08:20:00', 248);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-18 18:00:00', 249);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-18 19:20:00', 250);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-18 08:15:00', 251);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-18 09:25:00', 252);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-18 15:00:00', 253);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-18 16:10:00', 254);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-18 10:30:00', 255);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-18 13:30:00', 256);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-18 20:30:00', 257);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-18 23:30:00', 258);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-18 10:30:00', 259);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-18 14:00:00', 260);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-19 07:00:00', 261);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-19 08:30:00', 262);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-19 13:00:00', 263);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-19 14:30:00', 264);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-19 19:00:00', 265);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-19 20:30:00', 266);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-19 07:00:00', 267);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-19 08:20:00', 268);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-19 18:00:00', 269);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-19 19:20:00', 270);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-19 08:15:00', 271);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-19 09:25:00', 272);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-19 15:00:00', 273);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-19 16:10:00', 274);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-19 10:30:00', 275);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-19 13:30:00', 276);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-19 20:30:00', 277);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-19 23:30:00', 278);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-19 10:30:00', 279);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-19 14:00:00', 280);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-20 07:00:00', 281);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-20 08:30:00', 282);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-20 13:00:00', 283);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-20 14:30:00', 284);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-20 19:00:00', 285);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-20 20:30:00', 286);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-20 07:00:00', 287);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-20 08:20:00', 288);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-20 18:00:00', 289);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-20 19:20:00', 290);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-20 08:15:00', 291);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-20 09:25:00', 292);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-20 15:00:00', 293);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-20 16:10:00', 294);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-20 10:30:00', 295);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-20 13:30:00', 296);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-20 20:30:00', 297);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-20 23:30:00', 298);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-20 10:30:00', 299);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-20 14:00:00', 300);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-21 07:00:00', 301);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-21 08:30:00', 302);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-21 13:00:00', 303);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-21 14:30:00', 304);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-21 19:00:00', 305);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-21 20:30:00', 306);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-21 07:00:00', 307);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-21 08:20:00', 308);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-21 18:00:00', 309);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-21 19:20:00', 310);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-21 08:15:00', 311);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-21 09:25:00', 312);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-21 15:00:00', 313);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-21 16:10:00', 314);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-21 10:30:00', 315);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-21 13:30:00', 316);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-21 20:30:00', 317);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-21 23:30:00', 318);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-21 10:30:00', 319);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-21 14:00:00', 320);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-22 07:00:00', 321);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-22 08:30:00', 322);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-22 13:00:00', 323);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-22 14:30:00', 324);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-22 19:00:00', 325);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-22 20:30:00', 326);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-22 07:00:00', 327);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-22 08:20:00', 328);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-22 18:00:00', 329);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-22 19:20:00', 330);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-22 08:15:00', 331);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-22 09:25:00', 332);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-22 15:00:00', 333);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-22 16:10:00', 334);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-22 10:30:00', 335);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-22 13:30:00', 336);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-22 20:30:00', 337);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-22 23:30:00', 338);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-22 10:30:00', 339);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-22 14:00:00', 340);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-23 07:00:00', 341);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-23 08:30:00', 342);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-23 07:00:00', 345);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-23 08:20:00', 346);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-23 08:15:00', 349);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-23 09:25:00', 350);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-23 10:30:00', 353);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-23 13:30:00', 354);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-23 10:30:00', 357);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-23 14:00:00', 358);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-24 13:00:00', 343);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-24 14:30:00', 344);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-24 18:00:00', 347);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-24 19:20:00', 348);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-24 15:15:00', 351);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-24 16:25:00', 352);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-24 20:30:00', 355);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-24 23:30:00', 356);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-24 10:30:00', 359);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-24 14:00:00', 360);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-25 07:00:00', 361);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-25 08:30:00', 362);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-25 13:00:00', 363);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-25 14:30:00', 364);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-25 19:00:00', 365);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-25 20:30:00', 366);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-25 07:00:00', 367);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-25 08:20:00', 368);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-25 18:00:00', 369);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-25 19:20:00', 370);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-25 08:15:00', 371);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-25 09:25:00', 372);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-25 15:00:00', 373);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-25 16:10:00', 374);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-25 10:30:00', 375);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-25 13:30:00', 376);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-25 20:30:00', 377);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-25 23:30:00', 378);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-25 10:30:00', 379);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-25 14:00:00', 380);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-26 07:00:00', 381);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-26 08:30:00', 382);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-26 13:00:00', 383);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-26 14:30:00', 384);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-26 19:00:00', 385);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-26 20:30:00', 386);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-26 07:00:00', 387);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-26 08:20:00', 388);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-26 18:00:00', 389);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-26 19:20:00', 390);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-26 08:15:00', 391);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-26 09:25:00', 392);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-26 15:00:00', 393);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-26 16:10:00', 394);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-26 10:30:00', 395);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-26 13:30:00', 396);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-26 20:30:00', 397);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-26 23:30:00', 398);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-26 10:30:00', 399);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-26 14:00:00', 400);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-27 07:00:00', 401);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-27 08:30:00', 402);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-27 13:00:00', 403);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-27 14:30:00', 404);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-27 19:00:00', 405);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-27 20:30:00', 406);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-27 07:00:00', 407);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-27 08:20:00', 408);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-27 18:00:00', 409);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-27 19:20:00', 410);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-27 08:15:00', 411);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-27 09:25:00', 412);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-27 15:00:00', 413);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-27 16:10:00', 414);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-27 10:30:00', 415);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-27 13:30:00', 416);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-27 20:30:00', 417);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (28, '2015-05-27 23:30:00', 418);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-27 10:30:00', 419);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (32, '2015-05-27 14:00:00', 420);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-28 07:00:00', 421);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-28 08:30:00', 422);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-28 13:00:00', 423);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-28 14:30:00', 424);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-28 19:00:00', 425);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (16, '2015-05-28 20:30:00', 426);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-28 07:00:00', 427);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-28 08:20:00', 428);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-28 18:00:00', 429);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (20, '2015-05-28 19:20:00', 430);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-28 08:15:00', 431);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-28 09:25:00', 432);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-28 15:00:00', 433);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (24, '2015-05-28 16:10:00', 434);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-28 10:30:00', 435);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-28 13:30:00', 436);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-28 20:30:00', 437);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-28 23:30:00', 438);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-28 10:30:00', 439);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-28 14:00:00', 440);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-29 07:00:00', 441);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-29 08:30:00', 442);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-29 13:00:00', 443);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-29 14:30:00', 444);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-29 19:00:00', 445);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-29 20:30:00', 446);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-29 07:00:00', 447);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-29 08:20:00', 448);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-29 18:00:00', 449);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-29 19:20:00', 450);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-29 08:15:00', 451);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-29 09:25:00', 452);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-29 15:00:00', 453);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-29 16:10:00', 454);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-29 10:30:00', 455);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-29 13:30:00', 456);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-29 20:30:00', 457);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-29 23:30:00', 458);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-29 10:30:00', 459);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-29 14:00:00', 460);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-30 07:00:00', 461);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-30 08:30:00', 462);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-30 07:00:00', 465);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-30 08:20:00', 466);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-30 08:15:00', 469);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-30 09:25:00', 470);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-30 10:30:00', 473);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-30 13:30:00', 474);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-30 10:30:00', 477);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-30 14:00:00', 478);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-31 13:00:00', 463);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (18, '2015-05-31 14:30:00', 464);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-31 18:00:00', 467);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (22, '2015-05-31 19:20:00', 468);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-31 15:15:00', 471);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (26, '2015-05-31 16:25:00', 472);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-31 20:30:00', 475);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (30, '2015-05-31 23:30:00', 476);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-31 10:30:00', 479);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (34, '2015-05-31 14:00:00', 480);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-30 07:00:00', 461);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-30 08:30:00', 462);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-30 07:00:00', 465);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-30 08:20:00', 466);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-30 08:15:00', 469);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-30 09:25:00', 470);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-30 10:30:00', 473);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-30 13:30:00', 474);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-30 10:30:00', 477);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-30 14:00:00', 478);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-31 13:00:00', 463);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (19, '2015-05-31 14:30:00', 464);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-31 18:00:00', 467);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (23, '2015-05-31 19:20:00', 468);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-31 15:15:00', 471);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (27, '2015-05-31 16:25:00', 472);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-31 20:30:00', 475);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (31, '2015-05-31 23:30:00', 476);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-31 10:30:00', 479);
INSERT INTO staffschedule (emp_id, fdate, fschedule_id) VALUES (35, '2015-05-31 14:00:00', 480);


--
-- TOC entry 2266 (class 0 OID 159783)
-- Dependencies: 189
-- Data for Name: transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (1, 1, 1, 'buy', '2015-05-01 10:48:58.36');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (2, 1, 2, 'buy', '2015-05-01 10:49:05.501');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (3, 1, 3, 'buy', '2015-05-01 10:49:07.688');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (4, 1, 4, 'buy', '2015-05-01 10:49:10.126');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (5, 1, 5, 'buy', '2015-05-01 10:49:12.97');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (8, 1, 8, 'reserve', '2015-05-01 10:49:31.848');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (9, 1, 9, 'reserve', '2015-05-01 10:49:34.598');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (10, 1, 10, 'reserve', '2015-05-01 10:49:38.149');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (11, 1, 11, 'reserve', '2015-05-01 10:49:42.274');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (12, 1, 12, 'reserve', '2015-05-01 10:49:53.383');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (13, 1, 13, 'reserve', '2015-05-01 10:49:55.211');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (14, 1, 14, 'reserve', '2015-05-01 10:49:57.008');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (15, 1, 15, 'reserve', '2015-05-01 10:49:59.793');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (16, 21, 16, 'buy', '2015-05-01 10:50:13.84');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (17, 21, 17, 'buy', '2015-05-01 10:50:17.543');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (18, 21, 18, 'buy', '2015-05-01 10:50:19.328');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (19, 21, 19, 'buy', '2015-05-01 10:50:21.469');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (20, 21, 20, 'buy', '2015-05-01 10:50:23.891');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (21, 21, 21, 'reserve', '2015-05-01 10:50:35.329');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (22, 21, 22, 'reserve', '2015-05-01 10:50:39.379');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (23, 21, 23, 'reserve', '2015-05-01 10:50:40.942');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (24, 21, 24, 'reserve', '2015-05-01 10:50:42.504');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (25, 21, 25, 'reserve', '2015-05-01 10:50:44.489');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (26, 21, 26, 'reserve', '2015-05-01 10:50:48.02');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (27, 21, 27, 'reserve', '2015-05-01 10:50:57.301');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (28, 21, 28, 'reserve', '2015-05-01 10:50:59.02');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (29, 21, 29, 'reserve', '2015-05-01 10:51:00.915');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (30, 21, 30, 'reserve', '2015-05-01 10:51:03.18');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (31, 121, 31, 'buy', '2015-05-01 10:51:52.844');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (32, 121, 32, 'buy', '2015-05-01 10:51:55.672');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (33, 121, 33, 'buy', '2015-05-01 10:51:57.251');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (34, 121, 34, 'buy', '2015-05-01 10:51:59.032');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (35, 121, 35, 'buy', '2015-05-01 10:52:00.691');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (39, 121, 39, 'reserve', '2015-05-01 10:52:16.754');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (40, 121, 40, 'reserve', '2015-05-01 10:52:19.238');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (41, 121, 41, 'reserve', '2015-05-01 10:52:27.601');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (42, 121, 42, 'reserve', '2015-05-01 10:52:30.07');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (43, 121, 43, 'reserve', '2015-05-01 10:52:31.851');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (44, 121, 44, 'reserve', '2015-05-01 10:52:33.195');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (45, 121, 45, 'reserve', '2015-05-01 10:52:34.789');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (46, 141, 46, 'buy', '2015-05-01 10:53:09.64');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (47, 141, 47, 'buy', '2015-05-01 10:53:11.905');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (48, 141, 48, 'buy', '2015-05-01 10:53:13.733');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (49, 141, 49, 'buy', '2015-05-01 10:53:15.265');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (50, 141, 50, 'buy', '2015-05-01 10:53:17.265');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (51, 141, 51, 'reserve', '2015-05-01 10:53:25.487');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (52, 141, 52, 'reserve', '2015-05-01 10:53:28.878');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (53, 141, 53, 'reserve', '2015-05-01 10:53:30.503');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (54, 141, 54, 'reserve', '2015-05-01 10:53:32.019');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (55, 141, 55, 'reserve', '2015-05-01 10:53:33.378');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (56, 141, 56, 'reserve', '2015-05-01 10:53:36.159');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (57, 141, 57, 'reserve', '2015-05-01 10:53:37.816');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (58, 141, 58, 'reserve', '2015-05-01 10:53:39.425');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (59, 141, 59, 'reserve', '2015-05-01 10:53:41.472');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (60, 141, 60, 'reserve', '2015-05-01 10:53:43.662');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (61, 241, 61, 'buy', '2015-05-01 10:54:20.948');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (62, 241, 62, 'buy', '2015-05-01 10:54:23.622');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (63, 241, 63, 'buy', '2015-05-01 10:54:25.419');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (64, 241, 64, 'buy', '2015-05-01 10:54:27.076');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (65, 241, 65, 'buy', '2015-05-01 10:54:28.638');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (66, 241, 66, 'reserve', '2015-05-01 10:54:43.06');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (67, 241, 67, 'reserve', '2015-05-01 10:54:45.782');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (68, 241, 68, 'reserve', '2015-05-01 10:54:47.798');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (69, 241, 69, 'reserve', '2015-05-01 10:54:49.563');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (70, 241, 70, 'reserve', '2015-05-01 10:54:51.72');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (71, 241, 71, 'reserve', '2015-05-01 10:54:53.563');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (72, 241, 72, 'reserve', '2015-05-01 10:54:55.282');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (73, 241, 73, 'reserve', '2015-05-01 10:54:56.767');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (74, 241, 74, 'reserve', '2015-05-01 10:54:58.251');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (75, 241, 75, 'reserve', '2015-05-01 10:54:59.814');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (76, 261, 76, 'buy', '2015-05-01 10:55:15.255');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (77, 261, 77, 'buy', '2015-05-01 10:55:17.286');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (78, 261, 78, 'buy', '2015-05-01 10:55:18.989');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (79, 261, 79, 'buy', '2015-05-01 10:55:20.63');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (80, 261, 80, 'buy', '2015-05-01 10:55:22.864');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (81, 261, 81, 'reserve', '2015-05-01 10:55:33.181');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (82, 261, 82, 'reserve', '2015-05-01 10:55:34.806');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (83, 261, 83, 'reserve', '2015-05-01 10:55:36.4');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (84, 261, 84, 'reserve', '2015-05-01 10:55:37.946');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (85, 261, 85, 'reserve', '2015-05-01 10:55:39.712');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (86, 261, 86, 'reserve', '2015-05-01 10:55:42.743');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (87, 261, 87, 'reserve', '2015-05-01 10:55:44.572');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (88, 261, 88, 'reserve', '2015-05-01 10:55:46.621');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (89, 261, 89, 'reserve', '2015-05-01 10:55:48.371');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (90, 261, 90, 'reserve', '2015-05-01 10:55:50.574');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (91, 361, 91, 'buy', '2015-05-01 10:56:33.192');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (92, 361, 92, 'buy', '2015-05-01 10:56:35.067');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (93, 361, 93, 'buy', '2015-05-01 10:56:36.614');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (94, 361, 94, 'buy', '2015-05-01 10:56:37.989');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (95, 361, 95, 'buy', '2015-05-01 10:56:39.396');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (96, 361, 96, 'reserve', '2015-05-01 10:56:50.696');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (97, 361, 97, 'reserve', '2015-05-01 10:56:52.399');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (98, 361, 98, 'reserve', '2015-05-01 10:56:53.899');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (99, 361, 99, 'reserve', '2015-05-01 10:56:55.555');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (100, 361, 100, 'reserve', '2015-05-01 10:57:00.508');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (101, 361, 101, 'reserve', '2015-05-01 10:57:02.399');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (102, 361, 102, 'reserve', '2015-05-01 10:57:04.743');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (103, 361, 103, 'reserve', '2015-05-01 10:57:06.368');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (104, 361, 104, 'reserve', '2015-05-01 10:57:07.95');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (105, 361, 105, 'reserve', '2015-05-01 10:57:10.106');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (106, 381, 106, 'buy', '2015-05-01 10:57:27.091');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (107, 381, 107, 'buy', '2015-05-01 10:57:29.406');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (108, 381, 108, 'buy', '2015-05-01 10:57:31.172');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (109, 381, 109, 'buy', '2015-05-01 10:57:33.188');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (110, 381, 110, 'buy', '2015-05-01 10:57:35.391');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (115, 381, 115, 'reserve', '2015-05-01 10:57:53.098');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (116, 381, 116, 'reserve', '2015-05-01 10:57:55.863');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (117, 381, 117, 'reserve', '2015-05-01 10:57:58.02');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (118, 381, 118, 'reserve', '2015-05-01 10:57:59.629');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (119, 381, 119, 'reserve', '2015-05-01 10:58:01.223');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (120, 381, 120, 'reserve', '2015-05-01 10:58:02.989');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (6, 1, 6, 'buy', '2015-05-02 18:08:10.469');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (7, 1, 7, 'buy', '2015-05-02 18:08:57.014');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (36, 121, 36, 'buy', '2015-05-02 18:09:50.192');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (37, 121, 37, 'buy', '2015-05-02 18:10:05.437');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (38, 121, 38, 'buy', '2015-05-02 18:10:10.511');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (111, 381, 111, 'buy', '2015-05-02 18:10:45.982');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (112, 381, 112, 'buy', '2015-05-02 18:10:49.988');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (113, 381, 113, 'buy', '2015-05-02 18:10:53.654');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (114, 381, 114, 'buy', '2015-05-02 18:10:57.453');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (121, 141, 202, 'reserve', '2015-05-10 23:32:54.027');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (122, 141, 207, 'reserve', '2015-05-10 23:34:33.003');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (123, 201, 231, 'buy', '2015-05-10 23:53:49.995');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (124, 201, 235, 'buy', '2015-05-10 23:53:55.345');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (125, 201, 237, 'buy', '2015-05-10 23:53:57.568');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (126, 201, 95, 'buy', '2015-05-10 23:54:03.757');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (127, 201, 104, 'reserve', '2015-05-10 23:54:15.993');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (128, 201, 106, 'reserve', '2015-05-10 23:54:19.099');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (129, 201, 117, 'reserve', '2015-05-10 23:54:22.372');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (130, 201, 142, 'reserve', '2015-05-10 23:54:53.391');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (131, 201, 178, 'reserve', '2015-05-10 23:55:02.341');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (133, 201, 213, 'cancel', '2015-05-10 23:56:01.381');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (132, 201, 199, 'cancel', '2015-05-10 23:55:09.91');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (134, 201, 207, 'buy', '2015-05-10 23:59:51.652');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (135, 201, 78, 'reserve', '2015-05-11 00:02:01.039');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (136, 201, 52, 'reserve', '2015-05-11 00:02:08.183');
INSERT INTO transactions (t_id, fschedule_id, c_id, action, t_date) VALUES (137, 201, 124, 'reserve', '2015-05-11 00:02:17.858');


--
-- TOC entry 2274 (class 0 OID 159815)
-- Dependencies: 198
-- Data for Name: travelagency; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO travelagency (id, name, phone, address) VALUES (1, 'Dolphin Hellas Travel', '2109227772', 'Syngrou Avenue');
INSERT INTO travelagency (id, name, phone, address) VALUES (2, 'Fantasy Travel', '2103310530', 'Filellinon Street');
INSERT INTO travelagency (id, name, phone, address) VALUES (3, 'Travel Idea', '2103610222', 'Akadimias Street');
INSERT INTO travelagency (id, name, phone, address) VALUES (4, 'Crazy Holidays', '2310237696', 'Konstantinoupoleos Street');
INSERT INTO travelagency (id, name, phone, address) VALUES (5, 'Zorpidis', '2310231170', 'Egnatia Street');


--
-- TOC entry 2275 (class 0 OID 159818)
-- Dependencies: 199
-- Data for Name: waitinglist; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO waitinglist (tid) VALUES (11);
INSERT INTO waitinglist (tid) VALUES (12);
INSERT INTO waitinglist (tid) VALUES (13);
INSERT INTO waitinglist (tid) VALUES (14);
INSERT INTO waitinglist (tid) VALUES (15);
INSERT INTO waitinglist (tid) VALUES (26);
INSERT INTO waitinglist (tid) VALUES (27);
INSERT INTO waitinglist (tid) VALUES (28);
INSERT INTO waitinglist (tid) VALUES (29);
INSERT INTO waitinglist (tid) VALUES (30);
INSERT INTO waitinglist (tid) VALUES (41);
INSERT INTO waitinglist (tid) VALUES (42);
INSERT INTO waitinglist (tid) VALUES (43);
INSERT INTO waitinglist (tid) VALUES (44);
INSERT INTO waitinglist (tid) VALUES (45);
INSERT INTO waitinglist (tid) VALUES (56);
INSERT INTO waitinglist (tid) VALUES (57);
INSERT INTO waitinglist (tid) VALUES (58);
INSERT INTO waitinglist (tid) VALUES (59);
INSERT INTO waitinglist (tid) VALUES (60);
INSERT INTO waitinglist (tid) VALUES (71);
INSERT INTO waitinglist (tid) VALUES (72);
INSERT INTO waitinglist (tid) VALUES (73);
INSERT INTO waitinglist (tid) VALUES (74);
INSERT INTO waitinglist (tid) VALUES (75);
INSERT INTO waitinglist (tid) VALUES (86);
INSERT INTO waitinglist (tid) VALUES (87);
INSERT INTO waitinglist (tid) VALUES (88);
INSERT INTO waitinglist (tid) VALUES (89);
INSERT INTO waitinglist (tid) VALUES (90);
INSERT INTO waitinglist (tid) VALUES (101);
INSERT INTO waitinglist (tid) VALUES (102);
INSERT INTO waitinglist (tid) VALUES (103);
INSERT INTO waitinglist (tid) VALUES (104);
INSERT INTO waitinglist (tid) VALUES (105);
INSERT INTO waitinglist (tid) VALUES (116);
INSERT INTO waitinglist (tid) VALUES (117);
INSERT INTO waitinglist (tid) VALUES (118);
INSERT INTO waitinglist (tid) VALUES (119);
INSERT INTO waitinglist (tid) VALUES (120);
INSERT INTO waitinglist (tid) VALUES (121);
INSERT INTO waitinglist (tid) VALUES (122);
INSERT INTO waitinglist (tid) VALUES (135);
INSERT INTO waitinglist (tid) VALUES (136);
INSERT INTO waitinglist (tid) VALUES (137);


--
-- TOC entry 2054 (class 2606 OID 159822)
-- Name: aircraft_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY aircraft
    ADD CONSTRAINT aircraft_pkey PRIMARY KEY (code);


--
-- TOC entry 2058 (class 2606 OID 159824)
-- Name: airport_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY airport
    ADD CONSTRAINT airport_pkey PRIMARY KEY (code);


--
-- TOC entry 2061 (class 2606 OID 159826)
-- Name: authoritytests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY authoritytests
    ADD CONSTRAINT authoritytests_pkey PRIMARY KEY (testcode);


--
-- TOC entry 2063 (class 2606 OID 159828)
-- Name: cashier_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY cashier
    ADD CONSTRAINT cashier_pkey PRIMARY KEY (tid);


--
-- TOC entry 2065 (class 2606 OID 159830)
-- Name: customer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (id);


--
-- TOC entry 2067 (class 2606 OID 159832)
-- Name: expertise_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY expertise
    ADD CONSTRAINT expertise_pkey PRIMARY KEY (emp_id, aircraft_type);


--
-- TOC entry 2072 (class 2606 OID 159834)
-- Name: flight_days_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY flight_days
    ADD CONSTRAINT flight_days_pkey PRIMARY KEY (fcode, days);


--
-- TOC entry 2070 (class 2606 OID 159836)
-- Name: flight_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY flight
    ADD CONSTRAINT flight_pkey PRIMARY KEY (fcode);


--
-- TOC entry 2074 (class 2606 OID 159838)
-- Name: flightdone_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY flightdone
    ADD CONSTRAINT flightdone_pkey PRIMARY KEY (fschedule_id);


--
-- TOC entry 2078 (class 2606 OID 159840)
-- Name: flightschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY flightschedule
    ADD CONSTRAINT flightschedule_pkey PRIMARY KEY (fschedule_id);


--
-- TOC entry 2080 (class 2606 OID 159842)
-- Name: flightsprogram_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY flightsprogram
    ADD CONSTRAINT flightsprogram_pkey PRIMARY KEY (program_id);


--
-- TOC entry 2082 (class 2606 OID 159844)
-- Name: fsattendant_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY fsattendant
    ADD CONSTRAINT fsattendant_pkey PRIMARY KEY (emp_id);


--
-- TOC entry 2084 (class 2606 OID 159846)
-- Name: fsmonthlysalary_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY fsmonthlysalary
    ADD CONSTRAINT fsmonthlysalary_pkey PRIMARY KEY (fs_id, month, year);


--
-- TOC entry 2086 (class 2606 OID 159848)
-- Name: fspilots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY fspilots
    ADD CONSTRAINT fspilots_pkey PRIMARY KEY (emp_id);


--
-- TOC entry 2088 (class 2606 OID 159850)
-- Name: fstaff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY fstaff
    ADD CONSTRAINT fstaff_pkey PRIMARY KEY (id);


--
-- TOC entry 2093 (class 2606 OID 159852)
-- Name: gstaff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY gstaff
    ADD CONSTRAINT gstaff_pkey PRIMARY KEY (id);


--
-- TOC entry 2056 (class 2606 OID 159854)
-- Name: id; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY aircraft_type
    ADD CONSTRAINT id PRIMARY KEY (id);


--
-- TOC entry 2095 (class 2606 OID 159856)
-- Name: language_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_pkey PRIMARY KEY (lang_code);


--
-- TOC entry 2097 (class 2606 OID 159858)
-- Name: madetransaction_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY madetransaction
    ADD CONSTRAINT madetransaction_pkey PRIMARY KEY (id, t_id, type);


--
-- TOC entry 2099 (class 2606 OID 159860)
-- Name: reservation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY reservation
    ADD CONSTRAINT reservation_pkey PRIMARY KEY (tid);


--
-- TOC entry 2101 (class 2606 OID 159862)
-- Name: services_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_pkey PRIMARY KEY (emp_id, service_date, aircraft_id);


--
-- TOC entry 2103 (class 2606 OID 159864)
-- Name: spoken_langs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY spoken_langs
    ADD CONSTRAINT spoken_langs_pkey PRIMARY KEY (emp_id, lang_code);


--
-- TOC entry 2106 (class 2606 OID 159866)
-- Name: staffschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY staffschedule
    ADD CONSTRAINT staffschedule_pkey PRIMARY KEY (emp_id, fschedule_id);


--
-- TOC entry 2091 (class 2606 OID 159868)
-- Name: transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (t_id);


--
-- TOC entry 2108 (class 2606 OID 159870)
-- Name: travelagency_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY travelagency
    ADD CONSTRAINT travelagency_pkey PRIMARY KEY (id);


--
-- TOC entry 2110 (class 2606 OID 159872)
-- Name: waitinglist_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY waitinglist
    ADD CONSTRAINT waitinglist_pkey PRIMARY KEY (tid);


--
-- TOC entry 2059 (class 1259 OID 159873)
-- Name: airport_shortcut_idx; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX airport_shortcut_idx ON airport USING btree (shortcut);


--
-- TOC entry 2068 (class 1259 OID 159874)
-- Name: flight_dep_time_idx; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX flight_dep_time_idx ON flight USING btree (dep_time);


--
-- TOC entry 2075 (class 1259 OID 159875)
-- Name: flightschedule_aircraft_code_idx; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX flightschedule_aircraft_code_idx ON flightschedule USING btree (aircraft_code);


--
-- TOC entry 2076 (class 1259 OID 159876)
-- Name: flightschedule_fdate_idx; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX flightschedule_fdate_idx ON flightschedule USING btree (fdate);


--
-- TOC entry 2104 (class 1259 OID 159877)
-- Name: staffschedule_fdate_idx; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX staffschedule_fdate_idx ON staffschedule USING btree (fdate);


--
-- TOC entry 2089 (class 1259 OID 159878)
-- Name: transactions_c_id_idx; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX transactions_c_id_idx ON transactions USING btree (c_id);


--
-- TOC entry 2111 (class 2606 OID 159879)
-- Name: aircraft_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY aircraft
    ADD CONSTRAINT aircraft_type_id_fkey FOREIGN KEY (type_id) REFERENCES aircraft_type(id);


--
-- TOC entry 2112 (class 2606 OID 159884)
-- Name: cashier_tid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY cashier
    ADD CONSTRAINT cashier_tid_fkey FOREIGN KEY (tid) REFERENCES transactions(t_id);


--
-- TOC entry 2113 (class 2606 OID 159889)
-- Name: expertise_aircraft_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expertise
    ADD CONSTRAINT expertise_aircraft_type_fkey FOREIGN KEY (aircraft_type) REFERENCES aircraft_type(id);


--
-- TOC entry 2114 (class 2606 OID 159894)
-- Name: expertise_emp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expertise
    ADD CONSTRAINT expertise_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES fstaff(id);


--
-- TOC entry 2117 (class 2606 OID 159899)
-- Name: flight_days_fcode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flight_days
    ADD CONSTRAINT flight_days_fcode_fkey FOREIGN KEY (fcode) REFERENCES flight(fcode);


--
-- TOC entry 2115 (class 2606 OID 159904)
-- Name: flight_departure_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flight
    ADD CONSTRAINT flight_departure_fkey FOREIGN KEY (departure) REFERENCES airport(code);


--
-- TOC entry 2116 (class 2606 OID 159909)
-- Name: flight_destination_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flight
    ADD CONSTRAINT flight_destination_fkey FOREIGN KEY (destination) REFERENCES airport(code);


--
-- TOC entry 2118 (class 2606 OID 159914)
-- Name: flightdone_fschedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flightdone
    ADD CONSTRAINT flightdone_fschedule_id_fkey FOREIGN KEY (fschedule_id) REFERENCES flightschedule(fschedule_id);


--
-- TOC entry 2119 (class 2606 OID 159919)
-- Name: flightschedule_aircraft_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flightschedule
    ADD CONSTRAINT flightschedule_aircraft_code_fkey FOREIGN KEY (aircraft_code) REFERENCES aircraft(code);


--
-- TOC entry 2120 (class 2606 OID 159924)
-- Name: flightschedule_fprogram_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flightschedule
    ADD CONSTRAINT flightschedule_fprogram_id_fkey FOREIGN KEY (fprogram_id) REFERENCES flightsprogram(program_id);


--
-- TOC entry 2121 (class 2606 OID 159929)
-- Name: flightsprogram_aircraft_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flightsprogram
    ADD CONSTRAINT flightsprogram_aircraft_type_fkey FOREIGN KEY (aircraft_type) REFERENCES aircraft_type(id);


--
-- TOC entry 2122 (class 2606 OID 159934)
-- Name: flightsprogram_flight_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY flightsprogram
    ADD CONSTRAINT flightsprogram_flight_code_fkey FOREIGN KEY (flight_code) REFERENCES flight(fcode);


--
-- TOC entry 2123 (class 2606 OID 159939)
-- Name: fsattendant_emp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY fsattendant
    ADD CONSTRAINT fsattendant_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES fstaff(id);


--
-- TOC entry 2124 (class 2606 OID 159944)
-- Name: fsattendant_native_lang_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY fsattendant
    ADD CONSTRAINT fsattendant_native_lang_fkey FOREIGN KEY (native_lang) REFERENCES language(lang_code);


--
-- TOC entry 2125 (class 2606 OID 159949)
-- Name: fsmonthlysalary_fs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY fsmonthlysalary
    ADD CONSTRAINT fsmonthlysalary_fs_id_fkey FOREIGN KEY (fs_id) REFERENCES fstaff(id);


--
-- TOC entry 2126 (class 2606 OID 159954)
-- Name: fspilots_emp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY fspilots
    ADD CONSTRAINT fspilots_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES fstaff(id);


--
-- TOC entry 2129 (class 2606 OID 159959)
-- Name: madetransaction_t_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY madetransaction
    ADD CONSTRAINT madetransaction_t_id_fkey FOREIGN KEY (t_id) REFERENCES transactions(t_id);


--
-- TOC entry 2130 (class 2606 OID 159964)
-- Name: reservation_tid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY reservation
    ADD CONSTRAINT reservation_tid_fkey FOREIGN KEY (tid) REFERENCES transactions(t_id);


--
-- TOC entry 2131 (class 2606 OID 159969)
-- Name: services_aircraft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_aircraft_id_fkey FOREIGN KEY (aircraft_id) REFERENCES aircraft(code);


--
-- TOC entry 2132 (class 2606 OID 159974)
-- Name: services_emp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES gstaff(id);


--
-- TOC entry 2133 (class 2606 OID 159979)
-- Name: services_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_test_id_fkey FOREIGN KEY (test_id) REFERENCES authoritytests(testcode);


--
-- TOC entry 2134 (class 2606 OID 159984)
-- Name: spoken_langs_emp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY spoken_langs
    ADD CONSTRAINT spoken_langs_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES fsattendant(emp_id);


--
-- TOC entry 2135 (class 2606 OID 159989)
-- Name: spoken_langs_lang_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY spoken_langs
    ADD CONSTRAINT spoken_langs_lang_code_fkey FOREIGN KEY (lang_code) REFERENCES language(lang_code) ON UPDATE CASCADE;


--
-- TOC entry 2136 (class 2606 OID 159994)
-- Name: staffschedule_emp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY staffschedule
    ADD CONSTRAINT staffschedule_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES fstaff(id);


--
-- TOC entry 2137 (class 2606 OID 159999)
-- Name: staffschedule_fschedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY staffschedule
    ADD CONSTRAINT staffschedule_fschedule_id_fkey FOREIGN KEY (fschedule_id) REFERENCES flightschedule(fschedule_id);


--
-- TOC entry 2127 (class 2606 OID 160004)
-- Name: transactions_c_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY transactions
    ADD CONSTRAINT transactions_c_id_fkey FOREIGN KEY (c_id) REFERENCES customer(id);


--
-- TOC entry 2128 (class 2606 OID 160009)
-- Name: transactions_fschedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY transactions
    ADD CONSTRAINT transactions_fschedule_id_fkey FOREIGN KEY (fschedule_id) REFERENCES flightschedule(fschedule_id);


--
-- TOC entry 2138 (class 2606 OID 160014)
-- Name: waitinglist_tid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY waitinglist
    ADD CONSTRAINT waitinglist_tid_fkey FOREIGN KEY (tid) REFERENCES transactions(t_id);


--
-- TOC entry 2282 (class 0 OID 0)
-- Dependencies: 6
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2015-06-05 10:58:36

--
-- PostgreSQL database dump complete
--

