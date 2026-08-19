# Ansible Production Practices & Structure

## 1. Core mental model

A maintainable Ansible project separates three concerns:

| Concern | Responsibility |
|---|---|
| **Inventory** | Where Ansible connects |
| **Variables** | What differs between hosts/environments |
| **Playbooks/Roles** | What Ansible should do and how |

A useful mental model:

```text
                    Ansible
                       │
          ┌────────────┼────────────┐
          │            │            │
      Inventory      Variables   Playbooks
      "WHERE"        "VALUES"     "WHAT"
          │            │            │
       Hosts/        Config       Roles
       Groups       per env       "HOW"
```

Keep infrastructure topology out of playbook logic wherever possible.

---

# 2. Recommended production project structure

For dev/staging/prod:

```text
ansible/
├── ansible.cfg
│
├── inventories/
│   ├── dev/
│   │   ├── hosts.ini
│   │   └── group_vars/
│   │       ├── all.yml
│   │       └── private.yml
│   │
│   ├── staging/
│   │   ├── hosts.ini
│   │   └── group_vars/
│   │       ├── all.yml
│   │       └── private.yml
│   │
│   └── prod/
│       ├── hosts.ini
│       └── group_vars/
│           ├── all.yml
│           └── private.yml
│
├── playbooks/
│   ├── site.yml
│   ├── nginx.yml
│   └── deploy.yml
│
├── roles/
│   ├── nginx/
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── handlers/
│   │   │   └── main.yml
│   │   ├── templates/
│   │   ├── files/
│   │   ├── defaults/
│   │   │   └── main.yml
│   │   └── vars/
│   │       └── main.yml
│   │
│   └── application/
│       └── ...
│
└── requirements.yml
```

For a small learning project, you can start with:

```text
ansible/
├── inventory
├── playbooks/
├── roles/
└── group_vars/
```

Then introduce environment-specific inventories and roles as the project grows.

---

# 3. Environment separation

Do not create separate playbooks for dev, staging, and production just because the hosts differ.

Prefer:

```text
Same playbook/role
        │
        ├── dev inventory
        ├── staging inventory
        └── prod inventory
```

Run the same playbook against different inventories:

```bash
ansible-playbook -i inventories/dev/hosts.ini playbooks/nginx.yml

ansible-playbook -i inventories/staging/hosts.ini playbooks/nginx.yml

ansible-playbook -i inventories/prod/hosts.ini playbooks/nginx.yml
```

This reduces configuration drift.

---

# 4. Inventory design

A useful inventory models **logical infrastructure groups**, not individual playbook tasks.

Example:

```ini
[jump_hosts]
13.53.127.164

[private]
10.2.7.49
10.2.5.110

[aws_ec2:children]
jump_hosts
private

[aws_ec2:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../pem_keys/key.pem

[private:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ../pem_keys/key.pem -W %h:%p ubuntu@13.53.127.164"'
```

This creates:

```text
aws_ec2
├── jump_hosts
│   └── 13.53.127.164
└── private
    ├── 10.2.7.49
    └── 10.2.5.110
```

## Important: `:children`

Use:

```ini
[aws_ec2:children]
jump_hosts
private
```

to declare child groups.

Do **not** use:

```ini
[aws_ec2:jump_hosts]
```

That is not valid INI inventory group syntax.

---

# 5. Naming groups

Prefer group names that avoid hyphens:

```ini
[aws_ec2]
```

rather than:

```ini
[aws-ec2]
```

Ansible may warn about invalid characters in group names when hyphens or other characters are used.

Good examples:

```text
aws_ec2
jump_hosts
web_servers
app_servers
db_servers
monitoring
```

---

# 6. Parent groups vs host targeting

Given:

```text
aws_ec2
├── jump_hosts
└── private
```

these commands have different meanings:

```bash
ansible jump_hosts -i inventory -m ping
```

Targets only:

```text
13.53.127.164
```

```bash
ansible private -i inventory -m ping
```

Targets:

```text
10.2.7.49
10.2.5.110
```

```bash
ansible aws_ec2 -i inventory -m ping
```

Targets all hosts in the parent group.

## Host-pattern operators

`:` is a set operation, not parent/child navigation.

```text
aws_ec2:private
```

means:

```text
aws_ec2 OR private
```

Since `private` is already inside `aws_ec2`, this effectively targets all hosts in `aws_ec2`.

Intersection:

```text
aws_ec2:&private
```

means:

```text
aws_ec2 AND private
```

Exclusion:

```text
aws_ec2:!private
```

means:

```text
aws_ec2 EXCEPT private
```

For normal playbooks, prefer the simplest group:

```yaml
hosts: private
```

rather than unnecessarily using:

```yaml
hosts: "aws_ec2:&private"
```

---

# 7. Global variables vs group variables

If a variable should be available to every host in an inventory, use:

```text
group_vars/all.yml
```

Example:

```yaml
environment: dev
nginx_package: nginx
nginx_port: 8080
```

These variables are available to:

```text
jump_hosts
private
aws_ec2
```

and any other host in that inventory.

If a variable is specific to a group, use:

```text
group_vars/private.yml
```

Example:

```yaml
nginx_port: 8080
```

The filename is a convention that matches the group name. It is not inherently mandatory.

A useful structure:

```text
group_vars/
├── all.yml
├── private.yml
└── jump_hosts.yml
```

Think:

```text
all.yml          → global to inventory
private.yml      → private hosts only
jump_hosts.yml   → jump hosts only
```

---

# 8. Environment-specific variables

A clean environment structure is:

```text
inventories/
├── dev/
│   ├── hosts.ini
│   └── group_vars/
│       └── all.yml
│
├── staging/
│   ├── hosts.ini
│   └── group_vars/
│       └── all.yml
│
└── prod/
    ├── hosts.ini
    └── group_vars/
        └── all.yml
```

Dev:

```yaml
environment: dev
app_port: 8080
```

Staging:

```yaml
environment: staging
app_port: 8081
```

Production:

```yaml
environment: prod
app_port: 80
```

The playbook remains the same:

```yaml
- name: Configure application
  hosts: private

  tasks:
    - name: Display environment
      debug:
        msg: "Deploying to {{ environment }} on port {{ app_port }}"
```

This is preferable to duplicating playbooks per environment.

---

# 9. Variables in playbooks

Simple playbook variables:

```yaml
- name: Configure nginx
  hosts: private

  vars:
    nginx_package: nginx

  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: "{{ nginx_package }}"
        state: present
```

Use `{{ variable_name }}` to reference variables.

For production projects, keep environment-specific configuration outside the playbook when practical.

---

# 10. Command-line variables

Variables can be overridden with extra vars:

```bash
ansible-playbook \
  -i inventories/dev/hosts.ini \
  playbooks/deploy.yml \
  -e "version=1.5.2"
```

Playbook:

```yaml
- name: Deploy application
  ansible.builtin.debug:
    msg: "Deploying {{ version }}"
```

Use `-e` for explicit deployment parameters or temporary overrides.

Do not use command-line variables as a substitute for proper environment configuration.

---

# 11. Variable dictionaries

Group related configuration into dictionaries:

```yaml
nginx:
  package: nginx
  service: nginx
  port: 80
```

Reference:

```yaml
{{ nginx.package }}
{{ nginx.service }}
{{ nginx.port }}
```

Example:

```yaml
- name: Install nginx
  ansible.builtin.apt:
    name: "{{ nginx.package }}"
    state: present

- name: Start nginx
  ansible.builtin.service:
    name: "{{ nginx.service }}"
    state: started
```

This becomes useful as configuration grows.

---

# 12. Ansible facts

Ansible gathers facts about target machines.

Examples:

```yaml
{{ ansible_hostname }}
{{ ansible_distribution }}
{{ ansible_default_ipv4.address }}
{{ ansible_processor_vcpus }}
```

Inspect facts:

```bash
ansible private -i inventory -m ansible.builtin.setup
```

Use facts when behavior genuinely depends on the target system.

Avoid unnecessary fact gathering when a playbook does not need it.

---

# 13. Loops and variables

Example:

```yaml
vars:
  packages:
    - nginx
    - git
    - curl
    - vim

tasks:
  - name: Install packages
    ansible.builtin.apt:
      name: "{{ item }}"
      state: present
    loop: "{{ packages }}"
```

This avoids repeating nearly identical tasks.

---

# 14. Roles: move reusable configuration into roles

A playbook should describe **what should happen**, while a role encapsulates reusable implementation.

Instead of keeping everything in:

```yaml
nginx.yml
```

create:

```text
roles/nginx/
├── tasks/
│   └── main.yml
├── handlers/
│   └── main.yml
├── templates/
├── files/
├── defaults/
│   └── main.yml
└── vars/
    └── main.yml
```

Playbook:

```yaml
- name: Configure web servers
  hosts: private
  become: true

  roles:
    - nginx
```

This makes the role reusable across environments.

---

# 15. Use handlers for service restarts

Avoid restarting services unnecessarily.

Instead of:

```yaml
- name: Restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted
```

after every run, use a handler:

```yaml
- name: Configure nginx
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: Restart nginx

handlers:
  - name: Restart nginx
    ansible.builtin.service:
      name: nginx
      state: restarted
```

The handler runs only when the notifying task reports a change.

This supports Ansible's idempotent model.

---

# 16. Idempotency

Production Ansible should be **idempotent**:

> Running the playbook multiple times should converge the system to the desired state without repeatedly causing unnecessary changes.

Prefer:

```yaml
ansible.builtin.apt:
  name: nginx
  state: present
```

over blindly running:

```yaml
ansible.builtin.shell: apt install nginx
```

Prefer declarative modules:

```text
apt
service
user
file
copy
template
package
ansible.builtin.systemd
```

Use `shell`/`command` only when an appropriate module cannot express the operation.

---

# 17. Check mode and diff

Before production changes, inspect what Ansible plans to change:

```bash
ansible-playbook \
  -i inventories/prod/hosts.ini \
  playbooks/site.yml \
  --check
```

For files/templates, `--diff` can show changes:

```bash
ansible-playbook \
  -i inventories/prod/hosts.ini \
  playbooks/site.yml \
  --check \
  --diff
```

These are useful safeguards before applying changes.

---

# 18. SSH jump hosts / bastion hosts

A jump host is not automatically used merely because it is named:

```text
jump_hosts
```

The group name is only organizational.

You must explicitly configure SSH routing.

For example:

```ini
[private:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ../pem_keys/key.pem -W %h:%p ubuntu@13.53.127.164"'
```

The traffic path becomes:

```text
Laptop
   │
   │ SSH
   ▼
Jump host
13.53.127.164
   │
   │ SSH forwarding
   ▼
Private instance
10.2.7.49
```

A useful debugging principle:

1. Test direct SSH to the jump host.
2. Test SSH through the jump host to the private instance.
3. Then test Ansible.

Manual test:

```bash
ssh -i ../pem_keys/key.pem ubuntu@13.53.127.164
```

Proxy test:

```bash
ssh -i ../pem_keys/key.pem \
  -o 'ProxyCommand=ssh -i ../pem_keys/key.pem -W %h:%p ubuntu@13.53.127.164' \
  ubuntu@10.2.7.49
```

Then:

```bash
ansible private -i inventory -m ping
```

This isolates networking, SSH authentication, and Ansible configuration problems.

---

# 19. Important ProxyJump lesson

If using:

```text
ProxyJump
```

remember that the SSH process used to reach the jump host must also have access to the correct authentication key.

A debug trace can reveal that the proxy process is attempting:

```text
~/.ssh/id_ed25519
```

instead of the intended EC2 key.

If necessary, explicitly specify the key in the proxy command:

```ini
ansible_ssh_common_args='-o ProxyCommand="ssh -i ../pem_keys/key.pem -W %h:%p ubuntu@13.53.127.164"'
```

Always verify the exact SSH path independently before debugging Ansible.

---

# 20. Secrets and Ansible Vault

Do not commit plaintext secrets:

```yaml
db_password: SuperSecretPassword
```

Use Ansible Vault:

```bash
ansible-vault encrypt inventories/prod/group_vars/all/vault.yml
```

Then run:

```bash
ansible-playbook \
  -i inventories/prod/hosts.ini \
  playbooks/site.yml \
  --ask-vault-pass
```

Keep secret material separate from normal configuration where practical.

---

# 21. Prefer FQCNs in production code

Use fully qualified collection names:

```yaml
ansible.builtin.apt:
ansible.builtin.service:
ansible.builtin.template:
ansible.builtin.copy:
ansible.builtin.file:
```

Instead of:

```yaml
apt:
service:
template:
```

FQCNs make the source of modules explicit and reduce ambiguity as projects use more collections.

---

# 22. Validate inventory before running playbooks

Useful commands:

Show the inventory graph:

```bash
ansible-inventory -i inventories/dev/hosts.ini --graph
```

Show a host's resolved variables:

```bash
ansible-inventory \
  -i inventories/dev/hosts.ini \
  --host 10.2.7.49
```

Test connectivity:

```bash
ansible private -i inventories/dev/hosts.ini -m ansible.builtin.ping
```

Run with verbose SSH diagnostics when needed:

```bash
ansible private \
  -i inventories/dev/hosts.ini \
  -m ansible.builtin.ping \
  -vvv
```

---

# 23. Use `ansible.cfg`

A project-local `ansible.cfg` makes behavior predictable.

Example:

```ini
[defaults]
inventory = inventories/dev/hosts.ini
interpreter_python = auto_silent
retry_files_enabled = False
```

However, be careful about setting a default inventory when the repository supports multiple environments. For multi-environment projects, explicitly specifying:

```bash
-i inventories/prod/hosts.ini
```

is often safer for production execution.

---

# 24. Production safety practices

Before changing production:

```text
1. Validate inventory
2. Verify target hosts
3. Run --check
4. Review --diff where applicable
5. Confirm variables
6. Run against intended environment
7. Review changes
8. Verify application/service health
```

Useful commands:

```bash
ansible-inventory -i inventories/prod/hosts.ini --graph

ansible prod_group \
  -i inventories/prod/hosts.ini \
  -m ansible.builtin.ping

ansible-playbook \
  -i inventories/prod/hosts.ini \
  playbooks/site.yml \
  --check \
  --diff
```

Avoid making production inventory the implicit default when an accidental run against production would be dangerous.

---

# 25. Git and repository practices

A production Ansible repository should normally be version controlled.

Commit:

```text
playbooks/
roles/
inventories/*/hosts.ini
inventories/*/group_vars/
ansible.cfg
requirements.yml
```

Do not commit:

```text
private keys
plaintext passwords
cloud credentials
API tokens
unencrypted Vault files
```

Use `.gitignore` for local/private material:

```gitignore
*.pem
*.key
.vault_pass
```

Be careful: `.gitignore` does not remove files that were already committed. Remove sensitive files from Git history if they were accidentally committed.

---

# 26. A practical structure for your current AWS project

A good next-stage version of your current project would be:

```text
framer-aws-phase1/
│
├── ansible.cfg
│
├── inventories/
│   ├── dev/
│   │   ├── hosts.ini
│   │   └── group_vars/
│   │       └── all.yml
│   │
│   └── prod/
│       ├── hosts.ini
│       └── group_vars/
│           └── all.yml
│
├── playbooks/
│   ├── nginx.yml
│   └── site.yml
│
├── roles/
│   └── nginx/
│       ├── tasks/
│       │   └── main.yml
│       ├── handlers/
│       │   └── main.yml
│       ├── templates/
│       └── defaults/
│           └── main.yml
│
└── pem_keys/
    └── key.pem          # local only; never commit
```

Inventory:

```ini
[jump_hosts]
13.53.127.164

[private]
10.2.7.49
10.2.5.110

[aws_ec2:children]
jump_hosts
private

[aws_ec2:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../pem_keys/key.pem

[private:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ../pem_keys/key.pem -W %h:%p ubuntu@13.53.127.164"'
```

Playbook:

```yaml
- name: Configure private servers
  hosts: private
  become: true

  roles:
    - nginx
```

This gives you a clean separation:

```text
Inventory
    ↓
Where are my servers?
    ↓
Variables
    ↓
What values apply here?
    ↓
Playbook
    ↓
What should be done?
    ↓
Role
    ↓
How should it be done?
```

---

# 27. Key takeaways

### Inventory

- Model infrastructure using logical groups.
- Use `:children` for parent/child relationships.
- Use `hosts: private` when you want the private group.
- `aws_ec2:private` means OR, not "private inside aws_ec2".
- Use `aws_ec2:&private` for intersection when genuinely needed.
- Keep jump-host routing explicitly configured.

### Variables

- `group_vars/all.yml` → global to the inventory.
- `group_vars/private.yml` → private group only.
- Environment-specific values belong under the corresponding environment inventory.
- Avoid hardcoding environment-specific values in playbooks.
- Use Vault for secrets.

### Playbooks and roles

- Playbooks express orchestration.
- Roles contain reusable implementation.
- Prefer modules over shell commands.
- Keep tasks idempotent.
- Use handlers for service restarts.
- Prefer FQCNs such as `ansible.builtin.apt`.

### Production operations

- Separate dev/staging/prod inventories.
- Reuse the same playbooks and roles.
- Validate inventory before execution.
- Use `--check` and `--diff` before risky changes.
- Test SSH independently when diagnosing connectivity.
- Never commit private keys or plaintext secrets.
- Make production execution explicit rather than accidental.

## Golden rule

> **Keep "where", "what values", and "what to do" separate.**

```text
Inventory → WHERE
Variables → VALUES
Playbooks → WHAT
Roles     → HOW
Vault     → SECRETS
```

That separation is the foundation for an Ansible setup that can scale from a few EC2 instances to multiple environments and larger infrastructure without turning into a collection of duplicated playbooks.
