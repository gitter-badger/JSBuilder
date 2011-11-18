function ObjectLifeCicleManager(conf) {
   this.conf = conf;
   this.singleton_instances = {};
}

ObjectLifeCicleManager.prototype = {
   get_instance: function(name, prop) {
      if(this.singleton_instances[name] == null)
         this.singleton_instances[name] = this.instanciate(name);
      return this.singleton_instances[name]
   },
   instanciate: function(class_name, prop) {
      var pars = [];
      if(prop != null && prop.constructor != null){
         if(prop.constructor.length == null) {
               pars.push(JSON.stringify(this.construct_obj(prop.constructor)));
         } else {
            for(var i = 0; i < prop.constructor.length; i++) {
               pars.push(JSON.stringify(this.construct_obj(prop.constructor[i])));
            }
         }
      }

      var new_obj = eval("new " + class_name + "(" + pars.join(", ") + ")");

      if(prop != null && prop.setter != null){
         for(var attr in prop.setter) {
	   if(new_obj[attr] == null){
	     throw "'" + attr + "' is not a function, please review your IOC configuration";
	   }
	   eval("new_obj." + attr + "("+ JSON.stringify(this.construct_obj(prop.setter[attr])) + ")");
	 }
      }
      return new_obj;
   },
   get_obj: function(name) {
      if(this.conf[name] == null) throw "Class '" + name + "' not configured";
      var hash = this.conf[name];
      return this.construct_obj(hash);
   },
   construct_obj: function(hash) {
      for(var key in hash) {
         if(key == "singleton") {
            return this.get_instance(hash["singleton"], hash);
         } else if(key == "new") {
            return this.instanciate(hash["new"], hash);
         } else if(key == "string") {
            return hash["string"];
         } else if(key == "bool") {
            return hash["bool"] == "true";
         }
      }
   },
};
