## check_scaleway_bdd

This is a Nagios check that use Scalways's REST API  to check if the bdd is up and get metric
https://www.scaleway.com/en/developers/api/managed-database-postgre-mysql/

### prerequisites

This script uses theses libs : REST::Client, Data::Dumper, Monitoring::Plugin, JSON, Readonly

to install them type :

```
sudo cpan REST::Client Data::Dumper  Monitoring::Plugin JSON Readonly 
```

### Use case

```bash
check_scaleway_bdd.pl 1.1.2

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

check_scaleway_bdd2.pl is a Nagios check that use Scaleway s REST API to get bdd metrics and status

Usage: check_scaleway_bdd2.pl  -T <Token> -r <Scaleway region>  -N <BDD name> | -i <id> [-m <Metric_Name>] | -L  | -b -d <dbname> ] [-w <threshold> -c <threshold> ]

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -T, --Token=STRING
 Token for api authentication
 -N, --name=STRING
   instance name
 -i, --id=STRING
   instance id
 -a, --apiversion=string
  Scaleway API version
 -w, --warning=threshold
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -c, --critical=threshold
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -L, --listInstance
   Autodiscover instance
 -r, --region=STRING
  Scaleway region
 -m, --metric=STRING
  bdd metrics : disk_usage_percent | total_connections | mem_usage_percent | cpu_usage_percent | total_connections_percent
 -b, --backup
  check backup status and age
 -d, --dbname=STRING
  db name for backup check
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 30)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
```

sample  :

```bash
#list all database 
./check_scaleway_bdd.pl -T <Token> -r fr-par -L
#Check a db  
./check_scaleway_bdd.pl -T <Token> -r fr-par -N MyDatabaseName
#Recuperation d'une metrique
./check_scaleway_bdd.pl -T <Token> -r fr-par -N MyDatabaseName -m disk_usage_percent
./check_scaleway_bdd.pl -T <Token> -r fr-par -i MyDBUID -r fr-par -m disk_usage_percent
#check backup 
./check_scaleway_bdd.pl -T <Token> -r fr-par -i MyDBUID -r fr-par --backup --dbname=xxx 
```
you may get  :

```bash
#Lister les instances
<?xml version="1.0" encoding="utf-8"?><data>
<label name="MyDatabaseName"id="MyDBUID"/>
<label name="MyDatabaseName"id="MyDBUID"/>
<label name="MyDatabaseName"id="MyDBUID"/>
</data>
#BDD sate 
check_scaleway_bdd.pl OK - instance status ready engine MySQL-8 name MyDatabaseName id = MyDBUID
#get a metric
check_scaleway_bdd.pl OK - disk_usage_percent value 8.748 | disk_usage_percent_MyDBUID=8.748%;;
#check backup 
OK - backup instance_id = MyDBUID database_name xxx is 3.486h old
```

