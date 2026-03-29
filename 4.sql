

--Q1 Use COALESCE to display each student's nationality. If nationality is NULL, show 'Unknown'.

select first_name, last_name, coalesce(nationality, 'Unknown') as nationality
from students;
--   => to test
Update students
set nationality = null 
where first_name ='Sara'

--Q2 Use NULLIF to treat a GPA of 0.0 as NULL. Show student name, their real GPA, and a cleaned version where 0.0 becomes NULL.

select first_name, last_name, gpa as original_gpa ,nullif(gpa, 0.0) as new_gpa
from students;

--   => to test
Update students
set gpa = 0.0 
where first_name ='Sara'

--Q3 Combine COALESCE + NULLIF: show each student's GPA. If GPA is NULL or 0.0, display 'Not Evaluated'.

select first_name, last_name, gpa as original_gpa ,COALESCE(cast (nullif(gpa, 0.0) as text),'Not Evaluated' ) as new_gpa
from students;

/* Bonus : Use NULLIF to calculate average GPA per department, avoiding division by zero. Use COALESCE to
replace NULL results with 0. Show dept_name, student count, and safe average GPA.
*/
select 
    d.dept_name,
    count(s.student_id) as student_count,
    round(coalesce(avg(nullif(s.gpa, 0.0)), 0) , 3) as safe_avg_gpa
from students s
join departments d on s.dept_id = d.dept_id
group by d.dept_name
order by d.dept_name;

/*Q4 Create a temporary table temp_course_stats with: course_code, course_name,
enrolled_count, avg_grade. Then find courses where avg_grade is above 75.
*/
create temp table temp_course_stats as
select 
    c.course_code,
    c.course_name,
    count(e.student_id) as enrolled_count,        
    round(coalesce(avg(e.grade) , 0) ,2)as avg_grade                        
from courses c
left join enrollments e on c.course_id = e.course_id
group by c.course_code, c.course_name;

select *
from temp_course_stats
where avg_grade > 75
order by avg_grade ;

--Q5 Create a B-tree index on dept_id in the students table.

create index idx_students_dept_id on students using btree (dept_id);

--Q6 Create a UNIQUE index on the email column of students. Then try to insert a duplicate email and observe the error.

create unique index idx_students_email on students (email);

insert into students (first_name, last_name, email)
values ('Ahmed', 'Gaber', 'test@gmail.com');

--Q7 Create a Partial index on salary in professors — only for active professors (is_active = TRUE

create index idx_professors_salary_active
on professors (salary)
where is_active = true;

/*Q8Create a view called v_student_details showing: student_id, full_name, email, gpa,
dept_name, faculty_name. Query it to list students in dept_id = 3.
*/

create or replace view v_student_details as
select 
    s.student_id,
    s.dept_id,
    s.first_name || ' ' || s.last_name as full_name,
    s.email,
    s.gpa,
    d.dept_name,
    f.faculty_name
from students s
join departments d on s.dept_id = d.dept_id
join faculties f on d.faculty_id = f.faculty_id;

select *
from v_student_details
where dept_id = 3;

/*
Q9 Create an audit table enrollment_audit. Then create a BEFORE UPDATE trigger
on enrollments: if the grade changed, log old_grade, new_grade, student_id, changed_at,
changed_by into the audit table.
*/

	create table enrollment_audit (
    audit_id serial primary key,
    student_id int,
    old_grade numeric,
    new_grade numeric,
    changed_at timestamp default current_timestamp,
    changed_by text default current_user
);

create or replace function log_grade_change()
returns trigger as $$
begin
     
    if new.grade is distinct from old.grade then
        insert into enrollment_audit (
            student_id,
            old_grade,
            new_grade,
            changed_at,
            changed_by
        )
        values (
            new.student_id,
            old.grade,
            new.grade,
            current_timestamp,
            current_user
        );
    end if;

    return new;
end;
$$ language plpgsql;

create trigger trg_before_update_grade
before update on enrollments
for each row
execute function log_grade_change();

update enrollments
set grade = 86
where enrollment_id = 1;
/*Q10 Test the grade trigger: update the grade of enrollment_id = 1.
Verify the audit log was written. Then update again with the SAME grade and
confirm no new audit row.
*/
update enrollments
set grade = 86
where enrollment_id = 2;

select *
from enrollment_audit
where student_id = (
    select student_id 
    from enrollments 
    where enrollment_id = 1
);
--Q11 Create a BEFORE INSERT trigger on professors: if salary is NULL or below 5000, set it to 5000 automatically.

create or replace function set_min_salary()
returns trigger as $$
begin
    if new.salary is null or new.salary < 5000 then
        new.salary := 5000;
    end if;

    return new;
end;
$$ language plpgsql;

create trigger trg_before_insert_professors
before insert on professors
for each row
execute function set_min_salary();

insert into professors (first_name , last_name, salary , email)
values ('Ahmed' , 'gaber 2', 3000 ,'gaber@mail.com');

select * from professors where email ='gaber@mail.com'

/*Q12 Run a transaction that: (1) increases all professor salaries in dept_id=1 by 10%,
(2) inserts a log record into a salary_log table. Verify both changes then COMMIT.
*/
-- Creating log table first before solving
CREATE TABLE IF NOT EXISTS salary_log (
	log_id SERIAL PRIMARY KEY,
	prof_id INTEGER,
	old_salary NUMERIC,
	new_salary NUMERIC,
	changed_by TEXT DEFAULT CURRENT_USER,
	changed_at TIMESTAMPTZ DEFAULT NOW()
);

begin;


with updated as (
    update professors
    set salary = salary * 1.10
    where dept_id = 1
    returning prof_id, salary / 1.10 as old_salary, salary as new_salary
)


insert into salary_log (prof_id, old_salary, new_salary)
select prof_id, old_salary, new_salary
from updated;

select * from professors where dept_id = 1;

select * from salary_log order by changed_at desc;

 
commit;

select * from salary_log;

--Q13 Demonstrate ROLLBACK: delete all enrollments for student_id=1 inside a transaction, then ROLLBACK. Confirm the rows are still there.

select *
from enrollments
where student_id = 1;

begin;

delete from enrollments
where student_id = 1;
rollback;

/**Q14 Use SAVEPOINTs: in one transaction, increase faculty_id=1 budget by 500,000 (save SAVEPOINT), then increase faculty_id=2
budget by 500,000. Undo ONLY the second update using ROLLBACK TO SAVEPOINT, then COMMIT*//

begin;


update faculties
set budget = budget + 500000
where faculty_id = 1;


savepoint update_faculty_1;

update faculties
set budget = budget + 500000
where faculty_id = 2;

select * from faculties where faculty_id in (1, 2);

rollback to savepoint update_faculty_1;

select * from faculties where faculty_id in (1, 2);

commit;
/*Q15 Test SET ROLE: as registrar_user (readwrite), switch to uni_readonly only.
Try a SELECT (should work) and an INSERT (should fail). Then RESET ROLE.*/


create role uni_readonly;

create role registrar_user login password '1234';

grant select on all tables in schema public to uni_readonly;

grant select, insert, update, delete on all tables in schema public to registrar_user;
--prevent editing read only
grant uni_readonly to registrar_user;
select current_user;
set role uni_readonly;

select * from students ;
-- err no permission 
insert into students (first_name, last_name, email)
values ('Test', 'User', 'test@test.com');

reset role;

select current_user;

/*Q16 Revoke DELETE on the students table from uni_readwrite. Verify the privilege is gone.
Then revoke ALL privileges and remove student_portal from uni_readonly.*/

-- make the role bec is not existed

create role uni_readwrite;

grant select, insert, update, delete on all tables in schema public to uni_readwrite;

revoke delete on students from uni_readwrite;

--Verify the privilege is gone.
select has_table_privilege('uni_readwrite', 'students', 'delete');

-- revoke ALL privileges
revoke all privileges on students from uni_readonly;

-- emove student_portal from uni_readonly

revoke uni_readonly from student_portal;
/*Q17 Write the pg_dump commands to: (1) full backup of university_db (3) schema-only backup, (4) data-only backup.*/
--   University.backup file uploaded with the schema 
