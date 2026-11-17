--- Why are employees leaving?
--1. Which departments have the highest employee attrition rate?

SELECT
    d.dept_name,
    COUNT(*) AS total_employees,
    COUNT(*) FILTER (
        WHERE er.employment_status = 'terminated'
    ) AS terminated_employees,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE er.employment_status = 'terminated'
        ) / COUNT(*),
        2
    ) AS attrition_percentage
FROM employment_records er
JOIN departments d
    ON er.department_id = d.dept_id
GROUP BY d.dept_name
ORDER BY attrition_percentage DESC;


-- Key finding:
-- Sales and Customer Success have the highest percentage: 18.80%.
-- Each has 94 terminated records out of 500 total records.

-- Interpretation:
-- Both departments have the highest observed termination percentage.
-- This alone does not establish why employees left.

-- Limitation:
-- This is a percentage of records marked terminated,
-- not necessarily an annual attrition rate.

--02: Does job level relate to employee termination?
-- Business question: Does the termination percentage vary by job level?
SELECT
    j.job_level,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (
        WHERE er.employment_status = 'terminated'
    ) AS terminated_records,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE er.employment_status = 'terminated'
        ) / COUNT(*),
        2
    ) AS termination_percentage
FROM employment_records er
JOIN job_roles j
    ON er.role_id = j.role_id
GROUP BY j.job_level
ORDER BY termination_percentage DESC;



-- Analysis 03: Salary positioning and termination
-- Compare salary below, within, or above the stated role salary band.

SELECT
    CASE
        WHEN er.base_salary < j.salary_band_min
            THEN 'Below salary band'
        WHEN er.base_salary > j.salary_band_max
            THEN 'Above salary band'
        WHEN er.base_salary IS NULL
            THEN 'Salary missing'
        ELSE 'Within salary band'
    END AS salary_position,

    COUNT(*) AS total_records,

    COUNT(*) FILTER (
        WHERE er.employment_status = 'terminated'
    ) AS terminated_records,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE er.employment_status = 'terminated'
        ) / COUNT(*),
        2
    ) AS termination_percentage

FROM employment_records er
JOIN job_roles j
    ON er.role_id = j.role_id

GROUP BY salary_position
ORDER BY termination_percentage DESC;


SELECT
    COUNT(*) AS total_records,

    COUNT(*) FILTER (
        WHERE er.base_salary IS NULL
    ) AS missing_salary,

    COUNT(*) FILTER (
        WHERE j.salary_band_min IS NULL
    ) AS missing_min_band,

    COUNT(*) FILTER (
        WHERE j.salary_band_max IS NULL
    ) AS missing_max_band,

    COUNT(*) FILTER (
        WHERE er.base_salary < j.salary_band_min
    ) AS below_band,

    COUNT(*) FILTER (
        WHERE er.base_salary > j.salary_band_max
    ) AS above_band

FROM employment_records er
JOIN job_roles j
    ON er.role_id = j.role_id;



-- Analysis 04: Tenure at termination
-- Business question: How long had employees been employed
-- when their employment ended?

SELECT
    CASE
        WHEN er.ended_at - er.started_at < 365
            THEN 'Less than 1 year'
        WHEN er.ended_at - er.started_at < 1095
            THEN '1 to less than 3 years'
        ELSE '3 years or more'
    END AS tenure_at_termination,

    COUNT(*) AS terminated_employees,

    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_terminations

FROM employment_records er
WHERE er.employment_status = 'terminated'
  AND er.started_at IS NOT NULL
  AND er.ended_at IS NOT NULL

GROUP BY 1
ORDER BY
    CASE
        WHEN
            CASE
                WHEN er.ended_at - er.started_at < 365
                    THEN 'Less than 1 year'
                WHEN er.ended_at - er.started_at < 1095
                    THEN '1 to less than 3 years'
                ELSE '3 years or more'
            END = 'Less than 1 year' THEN 1
        WHEN
            CASE
                WHEN er.ended_at - er.started_at < 365
                    THEN 'Less than 1 year'
                WHEN er.ended_at - er.started_at < 1095
                    THEN '1 to less than 3 years'
                ELSE '3 years or more'
            END = '1 to less than 3 years' THEN 2
        ELSE 3
    END;



-- Analysis 05: Early departures by department
-- Define early departure as termination within the first 365 days.

SELECT
    d.dept_name,
    COUNT(*) AS early_terminations,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (),
        2
    ) AS share_of_all_early_terminations
FROM employment_records er
JOIN departments d
    ON er.department_id = d.dept_id
WHERE er.employment_status = 'terminated'
  AND er.ended_at IS NOT NULL
  AND er.started_at IS NOT NULL
  AND er.ended_at - er.started_at < 365
GROUP BY d.dept_name
ORDER BY early_terminations DESC;



-- Analysis 06: Early terminations as a share of department records
-- Note: This is a record-based comparison, not a formal cohort attrition rate.

SELECT
    d.dept_name,
    COUNT(*) AS total_employment_records,

    COUNT(*) FILTER (
        WHERE er.employment_status = 'terminated'
          AND er.ended_at - er.started_at < 365
    ) AS early_terminations,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE er.employment_status = 'terminated'
              AND er.ended_at - er.started_at < 365
        ) / COUNT(*),
        2
    ) AS early_termination_percentage

FROM employment_records er
JOIN departments d
    ON er.department_id = d.dept_id
GROUP BY d.dept_name
ORDER BY early_termination_percentage DESC;



-- Analysis 07: Performance review outcomes by employment status
-- Compare review outcomes for employees marked active vs terminated.

SELECT
    er.employment_status,
    pr.review_outcome,
    COUNT(*) AS review_count,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (
            PARTITION BY er.employment_status
        ),
        2
    ) AS percentage_within_status
FROM employment_records er
JOIN performance_reviews pr
    ON er.employee_id = pr.employee_id
GROUP BY
    er.employment_status,
    pr.review_outcome
ORDER BY
    er.employment_status,
    review_count DESC;

SELECT
    COUNT(*) AS total_reviews,
    COUNT(DISTINCT employee_id) AS employees_with_reviews
FROM performance_reviews;

-- Analysis 08: Latest review by employee
-- For terminated employees, only consider reviews on or before termination.
-- For active employees, use their latest available review.

WITH employee_latest_review AS (
    SELECT
        er.employee_id,
        er.employment_status,
        pr.review_date,
        pr.review_outcome,
        ROW_NUMBER() OVER (
            PARTITION BY er.employee_id
            ORDER BY pr.review_date DESC, pr.review_id DESC
        ) AS rn
    FROM employment_records er
    JOIN performance_reviews pr
        ON er.employee_id = pr.employee_id
    WHERE er.employment_status = 'active'
       OR (
            er.employment_status = 'terminated'
            AND pr.review_date <= er.ended_at
       )
)
SELECT
    employment_status,
    review_outcome,
    COUNT(*) AS employees,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (
            PARTITION BY employment_status
        ),
        2
    ) AS percentage_within_status
FROM employee_latest_review
WHERE rn = 1
GROUP BY employment_status, review_outcome
ORDER BY employment_status, employees DESC;



SELECT
    termination_type,
    COUNT(*) AS terminated_employees
FROM employment_records
WHERE employment_status = 'terminated'
GROUP BY termination_type
ORDER BY terminated_employees DESC;



SELECT
    termination_type,
    CASE
        WHEN ended_at - started_at < 365
            THEN 'Less than 1 year'
        WHEN ended_at - started_at < 1095
            THEN '1 to less than 3 years'
        ELSE '3 years or more'
    END AS tenure_group,
    COUNT(*) AS employee_count,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (PARTITION BY termination_type),
        2
    ) AS pct_within_exit_type
FROM employment_records
WHERE employment_status = 'terminated'
GROUP BY
    termination_type,
    CASE
        WHEN ended_at - started_at < 365
            THEN 'Less than 1 year'
        WHEN ended_at - started_at < 1095
            THEN '1 to less than 3 years'
        ELSE '3 years or more'
    END
ORDER BY termination_type, tenure_group;



SELECT
    MIN(started_at) AS earliest_start_date,
    MAX(started_at) AS latest_start_date,
    MIN(ended_at) AS earliest_termination_date,
    MAX(ended_at) AS latest_termination_date,
    COUNT(*) FILTER (
        WHERE ended_at - started_at < 365
    ) AS exits_under_one_year,
    COUNT(*) FILTER (
        WHERE ended_at - started_at >= 1095
    ) AS exits_after_three_years
FROM employment_records
WHERE employment_status = 'terminated';

