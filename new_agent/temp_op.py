import config

if config.op_sel_method == "random":
    print ("random method loaded")
    
elif config.op_sel_method == "Jev":
    print ("Jev method loaded")
else:
    raise ValueError("op_sel_method configured worng!!")


