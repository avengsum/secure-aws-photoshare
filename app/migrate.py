"""Run idempotent database schema migrations before the app starts."""

from app import get_db_connection


def main():
    connection = get_db_connection()
    if connection is None:
        raise RuntimeError("Database connection could not be established")

    try:
        with connection.cursor() as cursor:
            statements = open("/app/schema.sql", encoding="utf-8").read().split(";")

            for statement in statements:
                statement = statement.strip()
                if statement and not statement.upper().startswith(("CREATE DATABASE", "USE ")):
                    cursor.execute(statement)

        connection.commit()
        print("Database migrations completed")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
