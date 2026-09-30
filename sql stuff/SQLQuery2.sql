-- 1. Create a table for students
CREATE TABLE Students (
    StudentID INT PRIMARY KEY IDENTITY(1,1),
    FirstName VARCHAR(50),
    LastName VARCHAR(50),
    EnrollmentDate DATE DEFAULT GETDATE()
);
GO

-- 2. Add sample records
INSERT INTO Students (FirstName, LastName)
VALUES ('Alex', 'Morgan'),
       ('Taylor', 'Swift');
GO

-- 3. Retrieve all records
SELECT * FROM Students;