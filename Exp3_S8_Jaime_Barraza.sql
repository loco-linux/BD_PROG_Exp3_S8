-- -------------------------------------------------------
-- SCRIPT ESCRITO POR JAIME BARRAZA
-- PARA EL RAMO PROGRAMACION DE BASES DE DATOS
-- DESARROLLO DE APLICACIONES
-- DUOC UC 
-- FEBRERO-2025
-- ------------------------------------------------------- 



--------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------



-- ==========================================
-- PACKAGE pkg_liquidacion
-- Contiene la lógica para calcular liquidaciones
-- y registrar errores en ERROR_CALC
-- ==========================================
CREATE OR REPLACE PACKAGE pkg_liquidacion AS
    -- Variable global para almacenar el promedio de ventas del año anterior
    v_promedio_ventas NUMBER;
    
    -- Procedimiento para registrar errores en ERROR_CALC
    PROCEDURE registrar_error(
        p_subprograma   VARCHAR2,  -- Nombre del subprograma donde ocurrió el error
        p_mensaje       VARCHAR2,  -- Mensaje de error de Oracle
        p_descripcion   VARCHAR2   -- Descripción personalizada del error
    );
    
    -- Función para calcular el promedio de ventas del año anterior
    FUNCTION calcular_promedio_ventas RETURN NUMBER;
END pkg_liquidacion;
/


-- ==========================================
-- PACKAGE BODY pkg_liquidacion
-- Implementa la lógica del package
-- ==========================================
CREATE OR REPLACE PACKAGE BODY pkg_liquidacion AS

    -- Procedimiento para registrar errores en ERROR_CALC
    PROCEDURE registrar_error(
        p_subprograma   VARCHAR2,
        p_mensaje       VARCHAR2,
        p_descripcion   VARCHAR2
    ) IS
    BEGIN
        INSERT INTO ERROR_CALC (
            CORREL_ERROR, RUTINA_ERROR, DESCRIP_ERROR, DESCRIP_USER
        ) VALUES (
            SEQ_ERROR.NEXTVAL, p_subprograma, p_mensaje, p_descripcion
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE; -- Propaga el error para mejor trazabilidad
    END registrar_error;
    
    -- Función para calcular el promedio de ventas del año anterior
    FUNCTION calcular_promedio_ventas RETURN NUMBER IS
        v_suma_ventas NUMBER;
        v_num_boletas NUMBER;
        v_promedio    NUMBER;
    BEGIN
        -- Calcular el total de ventas del año anterior
        SELECT NVL(SUM(d.VALOR_TOTAL), 0)
          INTO v_suma_ventas
          FROM DETALLE_BOLETA d
          JOIN BOLETA b ON d.NRO_BOLETA = b.NRO_BOLETA
         WHERE EXTRACT(YEAR FROM b.FECHA) = EXTRACT(YEAR FROM SYSDATE) - 1;

        -- Calcular la cantidad de boletas del año anterior
        SELECT COUNT(DISTINCT b.NRO_BOLETA)
          INTO v_num_boletas
          FROM BOLETA b
         WHERE EXTRACT(YEAR FROM b.FECHA) = EXTRACT(YEAR FROM SYSDATE) - 1;

        -- Calcular el promedio de ventas
        v_promedio := CASE 
                        WHEN v_num_boletas > 0 THEN ROUND(v_suma_ventas / v_num_boletas) 
                        ELSE 0 
                      END;
        
        RETURN v_promedio;
    EXCEPTION
        WHEN OTHERS THEN
            registrar_error('calcular_promedio_ventas', SQLERRM, 'Error en cálculo de promedio de ventas');
            RAISE;
    END calcular_promedio_ventas;

END pkg_liquidacion;
/



-- ==========================================
-- FUNCIÓN obtener_pct_antiguedad
-- Retorna el porcentaje de asignación por antigüedad
-- basado en los años de servicio del empleado
-- ==========================================
CREATE OR REPLACE FUNCTION obtener_pct_antiguedad(
    p_anios NUMBER
) RETURN NUMBER IS
    v_pct NUMBER;
    v_count NUMBER;
BEGIN
    -- Verificar si hay duplicados en PCT_ANTIGUEDAD
    SELECT COUNT(*)
      INTO v_count
      FROM PCT_ANTIGUEDAD
     WHERE p_anios BETWEEN ANNOS_ANTIGUEDAD_INF AND ANNOS_ANTIGUEDAD_SUP;
    
    IF v_count > 1 THEN
        pkg_liquidacion.registrar_error('obtener_pct_antiguedad', 'DUPLICADO', 'Rango duplicado para ' || p_anios || ' años.');
        RETURN 0;
    END IF;
    
    -- Obtener porcentaje de antigüedad
    SELECT NVL(PORC_ANTIGUEDAD, 0)
      INTO v_pct
      FROM PCT_ANTIGUEDAD
     WHERE p_anios BETWEEN ANNOS_ANTIGUEDAD_INF AND ANNOS_ANTIGUEDAD_SUP
       AND ROWNUM = 1;
    
    RETURN v_pct;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        pkg_liquidacion.registrar_error('obtener_pct_antiguedad', 'NO_DATA_FOUND', 'No se encontró porcentaje para ' || p_anios || ' años.');
        RAISE;
    WHEN OTHERS THEN
        pkg_liquidacion.registrar_error('obtener_pct_antiguedad', SQLERRM, 'Error inesperado en cálculo de antigüedad.');
        RAISE;
END obtener_pct_antiguedad;
/


-- ==========================================
-- PROCEDIMIENTO calcular_liquidaciones
-- Procesa la liquidación de empleados
-- ==========================================
CREATE OR REPLACE PROCEDURE calcular_liquidaciones(
    p_anio NUMBER,
    p_mes  NUMBER
) IS
BEGIN
    -- Obtener y almacenar el promedio de ventas
    pkg_liquidacion.v_promedio_ventas := pkg_liquidacion.calcular_promedio_ventas;
    
    FOR v_empleado IN (
        SELECT * FROM EMPLEADO WHERE TIPO_EMPLEADO = 5
    ) LOOP
        DECLARE
            v_ventas NUMBER := 0;
            v_anios_servicio NUMBER;
            v_pct_antiguedad NUMBER;
            v_asig_antiguedad NUMBER;
            v_total_haberes NUMBER;
        BEGIN
            -- Obtener ventas del año anterior
            SELECT NVL(SUM(d.VALOR_TOTAL), 0)
              INTO v_ventas
              FROM DETALLE_BOLETA d
              JOIN BOLETA b ON d.NRO_BOLETA = b.NRO_BOLETA
             WHERE b.RUN_EMPLEADO = v_empleado.RUN_EMPLEADO
               AND EXTRACT(YEAR FROM b.FECHA) = p_anio - 1;

            v_anios_servicio := EXTRACT(YEAR FROM SYSDATE) - EXTRACT(YEAR FROM v_empleado.FECHA_CONTRATO);
            
            -- Obtener porcentaje de asignación por antigüedad
            v_pct_antiguedad := obtener_pct_antiguedad(v_anios_servicio);
            
            -- Calcular asignación y total de haberes
            v_asig_antiguedad := v_empleado.SUELDO_BASE * v_pct_antiguedad / 100;
            v_total_haberes := v_empleado.SUELDO_BASE + v_asig_antiguedad;
            
            -- Insertar en LIQUIDACION_EMPLEADO
            INSERT INTO LIQUIDACION_EMPLEADO (MES, ANNO, RUN_EMPLEADO, SUELDO_BASE, ASIG_ESPECIAL, TOTAL_HABERES)
            VALUES (p_mes, p_anio, v_empleado.RUN_EMPLEADO, v_empleado.SUELDO_BASE, v_asig_antiguedad, v_total_haberes);
        END;
    END LOOP;
    
    COMMIT;
END calcular_liquidaciones;
/



-- Impedir INSERT o DELETE en PRODUCTO de lunes a viernes
CREATE OR REPLACE TRIGGER trg_productos_no_ins_del
BEFORE INSERT OR DELETE ON PRODUCTO
FOR EACH ROW
BEGIN
    IF TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('MON','TUE','WED','THU','FRI') THEN
        IF INSERTING THEN RAISE_APPLICATION_ERROR(-20501, 'No se pueden insertar productos de lunes a viernes.');
        ELSIF DELETING THEN RAISE_APPLICATION_ERROR(-20500, 'No se pueden eliminar productos de lunes a viernes.');
        END IF;
    END IF;
END;
/


-- ==========================================
-- TEST 
-- ==========================================

-- Test 1: Intentar insertar o eliminar un producto un lunes
INSERT INTO PRODUCTO (COD_PRODUCTO, DESCRIPCION, VALOR_UNITARIO, TOTAL_STOCK)
VALUES (100, 'Nuevo Producto', 5000, 50); -- Debería lanzar error 

DELETE FROM PRODUCTO WHERE COD_PRODUCTO = 19; -- Debería lanzar error 



-- Test 2: Actualizar un producto a un precio permitido
UPDATE PRODUCTO SET VALOR_UNITARIO = 1000 WHERE COD_PRODUCTO = 19; -- Debe ejecutarse sin errores


-- Test 3: Actualizar un producto con un aumento mayor al 10%
UPDATE PRODUCTO SET VALOR_UNITARIO = 10000 WHERE COD_PRODUCTO = 19;
SELECT * FROM DETALLE_BOLETA WHERE COD_PRODUCTO = 19; -- Debería mostrar los valores recalculados




SELECT * FROM LIQUIDACION_EMPLEADO;

SELECT * FROM ERROR_CALC;
