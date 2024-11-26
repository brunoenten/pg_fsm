# [pg_fsm: Finite State Machine Extension for PostgreSQL](https://github.com/brunoenten/pg_fsm)

`pg_fsm` is a PostgreSQL extension that enables the implementation of finite state machines (FSM) directly within the database. This facilitates the modeling of complex workflows and state transitions using SQL, enhancing the management of state-driven processes.

## Features

- **Direct Integration**: Define and manage finite state machines within PostgreSQL.
- **Simplified Workflow Management**: Utilize SQL to handle state transitions and workflows.
- **Enhanced Data Integrity**: Enforce state constraints at the database level.

## Prerequisites

Before installing `pg_fsm`, ensure you have the following:

- PostgreSQL 9.6 or higher

## Installation

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/brunoenten/pg_fsm.git
   ```

2. **Navigate to the Directory**:

   ```bash
   cd pg_fsm
   ```

3. **Build and Install the Extension**:

   ```bash
   make
   sudo make install
   ```

4. **Load the Extension in PostgreSQL**:

   ```sql
   CREATE EXTENSION fsm;
   ```

## Usage

After installation, you can define states and transitions to model your workflows. For example, to create a simple state machine:

```sql
-- Define states
SELECT fsm.create_state('pending');
SELECT fsm.create_state('approved');
SELECT fsm.create_state('rejected');

-- Define transitions
SELECT fsm.create_transition('pending', 'approved', 'approve');
SELECT fsm.create_transition('pending', 'rejected', 'reject');
```

This setup allows transitions from 'pending' to 'approved' or 'rejected' based on the specified events.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your enhancements or bug fixes.

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE.txt](LICENSE.txt) file for details.

## Acknowledgments

Special thanks to the PostgreSQL community for their continuous support and development of the database system.

---

*Note: This extension is a community-driven project and is not officially supported by the PostgreSQL Global Development Group.* 
